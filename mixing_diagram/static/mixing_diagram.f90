!---------------------------------------------------------------------------------
! Purpose:
!
! !DESCRIPTION:  
! This subroutine calculates the full suite of mixing diagram variables when
! given a time series of of surface fluxes, surface 2m state variables, and 
! boundary layer height. Mixing diagram variables returned are surface bowen
! ratio, entrainment bowen ratio, advection ratios, and the various latent and 
! sensible heat fluxes associated with those ratios. The utility is to characterize 
! the coupling between surface fluxes and top of boundary layer fluxes in tandem
! with knowledge regarding soil moisture state.  More details regarding motivation
! can be found in the references below.
! 
!  References: Santanello et al. 2009,  A Modeling and Observational Framework 
!              for Diagnosing Local Land-Atmosphere Coupling on Diurnal Time Scales
!
!              Santanello et al. 2011,  Diagnosing the Sensitivity of Local 
!              Land-Atmosphere Coupling via the Soil Moisture-Boundary Layer Interaction
!
!              ** Comprehensive Evaluation **
!              Santanello et al. 2013, Diagnosing the Nature of L-A Coupling:
!              A Case Study of Dry/Wet Extremes in the U.S. Southern Great Plains  
!
! Author and Revision History: 
! Original Author of NCL scripts -- Jatin Kala  on Nov 2013
! Converted to F90 module        -- A.B. Tawfik on Apr 2015
!
!---------------------------------------------------------------------------------
module Mixing_Diag_Mod

     !
     ! subroutine name 
     !
     public mixing_diag

!---------------------------------------------------------------------------------
contains
!---------------------------------------------------------------------------------



!---------------------------------------------------------------------------------
!
! subroutines:  calculates mixing diagram variables using the INCREMENTAL more precise approach
!               Assumes left most dimension is time
!               Output can be dimensioned:  
!               (hours, spatial dimension like lat/lon)  or (days, spatial dimension like lat/lon)
!               This depends on the "average_daily" control switch below.  By default 
!               "average_daily = .true."  which calcualte average flux quantities for each day
!---------------------------------------------------------------------------------
  subroutine mixing_diag ( dim2       , ntim    , steps_per_day                               ,  &
                           t2m        , psfc    , q2m    ,  pbl_h  , shf    , lhf    , dt     ,  &
                           shf_ent    , lhf_ent , shf_sfc,  lhf_sfc, shf_tot, lhf_tot, evapf  ,  &
                           lcl_deficit, missing   )
   implicit none
!
! Input/Output Variables
!
   integer, intent(in   )                         ::  dim2           ! *** missing value - useful for obs
   integer, intent(in   )                         ::  ntim           ! *** total number of time slices
   integer, intent(in   )                         ::  steps_per_day  ! *** number of time steps per day
   real(4), intent(in   )                         ::  dt             ! *** time increment of the hours dimension [seconds]
 
   real(4), intent(in   )                         ::  missing        ! *** missing value - useful for obs
   real(4), intent(in   ), dimension(ntim,dim2)   ::  t2m, q2m, psfc ! *** 2m quantities - (days,hours) [K], [kg/kg], [Pa]
   real(4), intent(in   ), dimension(ntim,dim2)   ::  pbl_h          ! *** boundary layer height - (days,hours) [m]
   real(4), intent(in   ), dimension(ntim,dim2)   ::  shf, lhf       ! *** surface fluxes- dimensioned (days,hours) [W/m2]
   real(4), intent(out  ), dimension(ntim,dim2)   ::  shf_ent        ! *** entrainment flux of sensible heat [W/m2]
   real(4), intent(out  ), dimension(ntim,dim2)   ::  lhf_ent        ! *** entrainment flux of latent heat [W/m2]
   real(4), intent(out  ), dimension(ntim,dim2)   ::  shf_sfc        ! *** surface flux of sensible heat [W/m2]
   real(4), intent(out  ), dimension(ntim,dim2)   ::  lhf_sfc        ! *** surface flux of latent heat [W/m2]
   real(4), intent(out  ), dimension(ntim,dim2)   ::  shf_tot        ! *** Total flux of sensible heat [W/m2]
   real(4), intent(out  ), dimension(ntim,dim2)   ::  lhf_tot        ! *** Total flux of latent heat [W/m2]
   real(4), intent(out  ), dimension(ntim/steps_per_day,dim2), optional ::  evapf        ! *** daily evaporative fraction [unitless]
   real(4), intent(out  ), dimension(ntim,dim2)              , optional ::  lcl_deficit  ! *** lifted condensation level deficit (lcl - pbl) [m]
!
! Local variables
!
   real(4), parameter   ::  p_ref=1e5 , Lv=2.5e6, cp=1005.7
   real(4), parameter   ::  grav = 9.81, Rd=287.04, ep = 0.622, R_cp=Rd/cp
 
   integer                           ::  nday
   real(4), dimension(ntim,dim2)     ::  rho                  
   real(4), dimension(ntim,dim2)     ::  bowen_s             
   real(4), dimension(ntim,dim2)     ::  cp_theta_final      
   real(4), dimension(ntim,dim2)     ::  cp_theta_initial  
   real(4), dimension(ntim,dim2)     ::  cp_theta           
   real(4), dimension(ntim,dim2)     ::  cp_deltaT          
   real(4), dimension(ntim,dim2)     ::  Lv_qhum_initial      
   real(4), dimension(ntim,dim2)     ::  Lv_qhum_final     
   real(4), dimension(ntim,dim2)     ::  Lv_qhum         
   real(4), dimension(ntim,dim2)     ::  Lv_q_0          
   real(4), dimension(ntim,dim2)     ::  cp_T_0             
 
   real(4), dimension(ntim,dim2)     ::  lhf0             
   real(4), dimension(ntim,dim2)     ::  shf0           
   real(4), dimension(ntim,dim2)     ::  lhfi0           
   real(4), dimension(ntim,dim2)     ::  shfi0          
   real(4), dimension(ntim,dim2)     ::  lhfs0      
   real(4), dimension(ntim,dim2)     ::  shfs0     

   real(4), dimension(ntim,dim2)     ::  theta
   real(4), dimension(ntim,dim2)     ::  tsat
   real(4), dimension(ntim,dim2)     ::  plcl
   real(4), dimension(ntim,dim2)     ::  hlcl
   real(4), dimension(ntim,dim2)     ::  tvirt

   real(4), dimension(ntim/steps_per_day              ,dim2)  ::  shf_sum     
   real(4), dimension(ntim/steps_per_day              ,dim2)  ::  lhf_sum     
   real(4), dimension(ntim/steps_per_day,steps_per_day,dim2)  ::  shf_day     
   real(4), dimension(ntim/steps_per_day,steps_per_day,dim2)  ::  lhf_day     

!-----------------------------------------------------------------------------


      !--------------------------------------------
      !--- Initialization and preliminary calculations
      !--------------------------------------------
      !--------------------------------
      !-- initialize output arrays
      !--------------------------------
      shf_ent    =  missing
      lhf_ent    =  missing
      shf_sfc    =  missing
      lhf_sfc    =  missing
      shf_tot    =  missing
      lhf_tot    =  missing
      if( present(evapf      ) ) evapf        =  missing
      if( present(lcl_deficit) ) lcl_deficit  =  missing
    
      !--------------------------------
      !-- initialize working arrays
      !--------------------------------
      nday       =  ntim/steps_per_day
      bowen_s    =  missing
      rho        =  missing
      Lv_qhum    =  missing
      cp_theta   =  missing
      shf0       =  missing
      lhf0       =  missing
      shfi0      =  missing
      lhfi0      =  missing
      shfs0      =  missing
      lhfs0      =  missing

      cp_T_0     =  missing
      Lv_q_0     =  missing

      Lv_qhum_initial   =  missing
      Lv_qhum_final     =  missing
      cp_theta_initial  =  missing
      cp_theta_final    =  missing

      !-----------------------------------------------------------------------------------
      !-- Approximate air density (kg/m3)
      !-----------------------------------------------------------------------------------
      where( t2m.ne.missing .and. psfc.ne.missing .and. q2m.ne.missing ) 
         rho  =  psfc / (Rd * t2m * ((1. + (q2m/ep)) / (1. + q2m)))
      endwhere

      !-----------------------------------------------------------------------------------
      !-- Calculate 2-m potential temperature  * specific heat capacity (J/kg)
      !-----------------------------------------------------------------------------------
      !  where( t2m.ne.missing .and. psfc.ne.missing )  cp_theta  =  cp * (t2m * ((p_ref/psfc))**(R_cp))
      where( t2m.ne.missing .and. psfc.ne.missing )  cp_theta  =  cp * t2m 

      !-----------------------------------------------------------------------------------
      !-- Calculate 2-m specific humidity  * latent heat of vaporization (J/kg)
      !-----------------------------------------------------------------------------------
      where( q2m.ne.missing                       )  Lv_qhum   =  Lv * q2m

      !-----------------------------------------------------------------------------------
      !-- Calculate surface bowen ratio (unitless)
      !-----------------------------------------------------------------------------------
      where( lhf.ne.0 .and. shf.ne.missing .and. lhf.ne.missing )  bowen_s  =  shf/lhf


      
      !--------------------------------------------
      !--- Proceed to calculating output variables
      !--------------------------------------------
      !-----------------------------------------------------------------------------------
      !-- Surface heat and moisture vector components (see Eq 1 in Santanello et al. 2009)
      !-----------------------------------------------------------------------------------
      where( shf.ne.missing .and. rho.ne.missing .and. pbl_h.ne.missing .and. rho*pbl_h.ne.0 ) 
         cp_deltaT  =  (shf*dt) / (rho*pbl_h)
      elsewhere 
         cp_deltaT  =  missing
      endwhere


      !-----------------------------------------------------------------------------------
      !-- Define the start and end times of the increment for sensible and latent heat
      !-----------------------------------------------------------------------------------
      cp_theta_initial(2:,:)   =   cp_theta(:ntim-1,:) !*** start of time increment
      cp_theta_final           =   cp_theta            !*** end of time increment
      Lv_qhum_initial (2:,:)   =   Lv_qhum (:ntim-1,:) !*** start of time increment
      Lv_qhum_final            =   Lv_qhum             !*** end of time increment

      where( Lv_qhum_initial.ne.missing .and. cp_deltaT.ne.missing .and. bowen_s.ne.missing )
             Lv_q_0  =  Lv_qhum_initial   +  (cp_deltaT/bowen_s)
      end where
      where( cp_theta_initial.ne.missing .and. cp_deltaT.ne.missing )
             cp_T_0  =  cp_theta_initial  +  cp_deltaT
      end where


      !--------------------------------------------------
      ! output arrays
      !--------------------------------------------------
      !*********************************************************************************
      !******
      !******  --- STEPWISE ---
      !******  Hourly mixing diagram variables (based on dt, so not exactly hourly)
      !******
      !*********************************************************************************

      !--------------------------------------------------
      ! Calculate Heat budget in Wm-2
      !--------------------------------------------------
      where( cp_theta_final.ne.missing .and. rho.ne.missing .and. pbl_h.ne.missing .and. cp_T_0.ne.missing ) 
         shf0    =  (((cp * ((cp_theta_final/cp)  -  &
                      (cp_theta_initial/cp)))) * (rho * pbl_h))/(dt)
         shfi0   =  (((cp * ((cp_theta_final/cp)  -  &
                      (cp_T_0          /cp)))) * (rho * pbl_h))/(dt)
      endwhere

      !--------------------------------------------------
      !****  Total sensible heat Wm-2
      !--------------------------------------------------
      shf_tot  =  shf0

      !--------------------------------------------------
      !****  Entrainment sensible heat Wm-2
      !--------------------------------------------------
      shf_ent  =  shfi0

      !--------------------------------------------------
      !****  Surface sensible heat Wm-2
      !--------------------------------------------------
      where( cp_theta_initial.ne.missing .and. rho.ne.missing .and. pbl_h.ne.missing .and. cp_T_0.ne.missing ) 
         shfs0    =  (((cp * ((cp_T_0        /cp)  -  &
                       (cp_theta_initial/cp)))) * (rho * pbl_h))/(dt)
      endwhere
      shf_sfc  =  shfs0


      !--------------------------------------------------
      !Calculate Moisture Budget in Wm-2
      !--------------------------------------------------
      where( Lv_qhum_final.ne.missing .and. rho.ne.missing .and. pbl_h.ne.missing .and. Lv_q_0.ne.missing ) 
         lhf0    =  (((Lv * ((Lv_qhum_final/Lv)  -  &
                      (Lv_qhum_initial/Lv)))) * (rho * pbl_h))/(dt)
         lhfi0   =  (((Lv * ((Lv_qhum_final/Lv)  -  &
                      (Lv_q_0         /Lv)))) * (rho * pbl_h))/(dt)
      endwhere

      !--------------------------------------------------
      !****  Total latent heat Wm-2
      !--------------------------------------------------
      lhf_tot  =  lhf0

      !--------------------------------------------------
      !****  Entrainment latent heat Wm-2
      !--------------------------------------------------
      lhf_ent  =  lhfi0

      !--------------------------------------------------
      !****  Surface latent heat Wm-2
      !--------------------------------------------------
      where( Lv_qhum_initial.ne.missing .and. rho.ne.missing .and. pbl_h.ne.missing .and. Lv_q_0.ne.missing ) 
         lhfs0   =  (((Lv * ((Lv_q_0        /Lv)  -  &
                      (Lv_qhum_initial/Lv)))) * (rho * pbl_h))/(dt)
      endwhere
      lhf_sfc  =  lhfs0 




      !-----------------------------------------------------------------------------------
      !-- Calculate daily surface evaporative fraction (unitless)
      !-- Evap Fraction is calculated by summing the LH and SH fluxes throughout the 
      !-- day and then calculate a divide the cumulative LH daily flux by the sum of
      !-- sensible and latent heat flux sums
      !-----------------------------------------------------------------------------------
      if( present(evapf) ) then
         
          shf_day  =  missing
          lhf_day  =  missing
          shf_sum  =  missing
          lhf_sum  =  missing

          shf_day  =  reshape( shf, (/nday,steps_per_day,dim2/) )  
          lhf_day  =  reshape( lhf, (/nday,steps_per_day,dim2/) )  
          shf_sum  =  sum(shf_day, DIM = 2, MASK = shf_day.ne.missing .and. lhf_day.ne.missing )
          lhf_sum  =  sum(lhf_day, DIM = 2, MASK = shf_day.ne.missing .and. lhf_day.ne.missing )
          where( lhf_sum+shf_sum.ne.0  .and.  shf_sum.ne.missing   .and.  lhf_sum.ne.missing  ) 
             evapf  =  lhf_sum/(shf_sum+lhf_sum)
          endwhere
      end if



      !-----------------------------------------------------------------------------------
      !-- Calculate LCL Deficit (meters)
      !-- The LCL deficit is defined as the difference between the lifted condensation level
      !-- and the boundary layer height.  When the LCL deficit in negative then a necessary but
      !-- criterion for convective initiation is met.  
      !-- LCL is calculated using the Bolton 1980 empirical relationships
      !--        David Bolton, 1980: The Computation of Equivalent Potential Temperature. 
      !--        Mon. Wea. Rev., 108, 1046–1053.
      !-- To convert from pressure of LCL to height use the hypsometric equation
      !-- Note one assumption made here that is consistent with the mixing diagram assumption
      !-- is that 2m temperature (t2m) is representative of the mean boundary layer temperature
      !-----------------------------------------------------------------------------------
      if( present(lcl_deficit) ) then

          theta  =  missing
          tsat   =  missing
          plcl   =  missing
          hlcl   =  missing
          tvirt  =  missing

          where( t2m  .ne.missing .and. psfc.ne.missing )   theta   =   t2m  * (1e5/psfc)**R_cp
          where( theta.ne.missing .and. q2m .ne.missing )   
               tsat    =   55. + (2840./ (3.5*log(theta) - log(1e6*q2m/(622.+(1e3*q2m))) - 4.805))
          endwhere
          where( theta.ne.missing .and. tsat.ne.missing )   plcl    =   1e3 * (tsat/theta) ** 3.4965
          where( t2m  .ne.missing .and. q2m .ne.missing )   tvirt   =   t2m  * (1. + (0.61*q2m))
          where( tvirt.ne.missing .and. plcl.ne.missing .and. psfc.ne.missing ) 
               hlcl  =  (Rd*tvirt) / (grav) * log((psfc/1e2)/plcl)
          endwhere
          where( hlcl.ne.missing .and. pbl_h.ne.missing )   lcl_deficit  =  hlcl - pbl_h

      end if



      return

end subroutine mixing_diag



end module Mixing_Diag_Mod
