!#define DEBUG_L3
! #define DEBUG_COMPARE

!======================================================================================================================!
!
!                    DassFlow Version 2.0
!
!======================================================================================================================!
!
!  Copyright University of Toulouse-INSA - CNRS (France)
!
!  This file is part of the DassFlow software (Data Assimilation for Free Surface Flows).
!  DassFlow is a computational software aiming at simulating geophysical free surface flows.
!  It is designed for Variational Data Assimilation (4D-var) and sensitivity analyses. 
! Inverse capabilities are based on the adjoint code which is generated by 
! a source-to-source algorithmic differentiation (Tapenade software used).
!
!  DassFlow software includes few mostly independent "modules" with common architectures and structures:
!    - DassFlow 2DShallow (shallow water equations in (h,q), finite volumes), i.e. the present code.
!    - DassFlow3D  (non-linear Stokes equations, finite elements, mobile geometries, ALE).
!    - DassFlow 1D (shallow water equations in (S,Q), finite volumes or finite differences), river hydraulics.
!  Please consult the DassFlow webpage for more details: http://www.math.univ-toulouse.fr/DassFlow
!
! You have used DassFlow in an article, a scientific document etc ?  How to cite us ? Please consult the webpage.
! 
!  Many people have contributed to the DassFlow developments from the initial version to the latest ones.
!  Current main developers or scientific contributers are:
!               K. Larnier (CS & Mathematics Institute of Toulouse & INSA Toulouse)
!               P. Brisset (CNES & Mathematics Institute of Toulouse & INSA Toulouse)
!               F. Couderc (CNRS & Mathematics Institute of Toulouse IMT)
!               P.-A. Garambois (INSA Strasbourg & ICUBE Strasbourg)
!               L. Pujol (CNES & INSA Strasbourg & ICUBE Strasbourg)
!               J. Monnier (INSA & Mathematics Institute of Toulouse IMT).
!               J.-P. Vila (INSA & Mathematics Institute of Toulouse IMT).
!  and former other developers (R. Madec, M. Honnorat and J. Marin).
!
!  Scientific contact : jerome.monnier@insa-toulouse.fr
!  Technical  contacts : frederic.couderc@math.univ-toulouse.fr, pierre.brisset@insa-toulouse.fr, kevin.larnier@c-s.fr
!
!  This software is governed by the CeCILL license under French law and abiding by the rules of distribution
!  of free software. You can use, modify and/or redistribute the software under the terms of the CeCILL license
!  as circulated by CEA, CNRS and INRIA at the following URL: "http://www.cecill.info".
!
!  As a counterpart to the access to the source code and rights to copy, modify and redistribute granted by the
!  license, users are provided only with a limited warranty and the software's author, the holder of the economic
!  rights, and the successive licensors have only limited liability.
!
!  In this respect, the user's attention is drawn to the risks associated with loading, using, modifying and/or
!  developing or reproducing the software by the user in light of its specific status of free software, that may
!  mean that it is complicated to manipulate, and that also therefore means that it is reserved for developers and
!  experienced professionals having in-depth computer knowledge. Users are therefore encouraged to load and test the
!  software's suitability as regards their requirements in conditions enabling the security of their systems and/or
!  data to be ensured and, more generally, to use and operate it in the same conditions as regards security.
!
!  The fact that you are presently reading this means that you have had knowledge of the CeCILL license and that you
!  accept its terms.
!
!======================================================================================================================!
!> \file preissmann_time_step.f90
!! \brief This file includes the computation with Preissmann method with LPI with double sweep resolution. An unique subroutine :
!! preissmann

!> Subroutine of the computation with Preissmann method with LPI with double sweep resolution.
!!
!! \details Algorithm used:
!!
!!     Update boundaries conditions
!!     Update mvector
!!     Update of S,Q,H
!!     Write coefficient for the double sweep with LPI term
!!     Double sweep
!!     Get new S,Q
!!
!! For more details on the double sweep resolution see documentation.
!! \param[in]  dof Unknowns of the model.
!! \param[in]    msh Mesh of the model.


!**********************************************************************************************************************!
!**********************************************************************************************************************!
!
!  Perform Preissmann double sweep with LPI to Shallow-Water Equations
!
!**********************************************************************************************************************!
!**********************************************************************************************************************!


#ifdef DEBLOCK
SUBROUTINE preissmann_double_sweep_LPI( dof , msh )

   USE m_common
   USE m_mesh
   USE m_time_screen          !NOADJ
   USE m_model
   USE m_linear_solver        !NOADJ
   USE m_user_data
   USE m_numeric
   implicit none

!======================================================================================================================!
!  Interface Variables
!======================================================================================================================!

   TYPE(Mesh), intent(in   )  ::  msh
   TYPE( unk ), intent(inout)  ::  dof

!======================================================================================================================!
!  Local Variables
!======================================================================================================================!

   real(rp) :: sigma          ! Value of sigma in the preissmann scheme

   ! Definition C coefficients
   real(rp) :: Cb1,Cb2,Cb3          ! Coefficient Cb1,Cb2,Cb3
   real(rp) :: Cc1,Cc4,Cc5          ! Coefficient Cc1,Cc4,Cc5
   real(rp) :: Cd1,Cd4,Cd5          ! Coefficient Cd1,Cd4,Cd5
   real(rp) :: Ce2,Ce3              ! Coefficient Ce2,Ce3
   real(rp) :: Clat1,Clat2          ! Coefficient Clat1,Clat2 
   real(rp) :: Cl1,Cl2,Cl3,Cl4,Cl5  ! Coefficient Cl1,Cl2,Cl3,Cl4,Cl5
   real(rp) :: Cf1,Cf2,Cf3,Cf4,Cf5  ! Coefficient Cf1,Cf2,Cf3,Cf4,Cf5
   real(rp) :: Cg,Ch,Ci,Cj,Ck       ! Coefficient Cg,Ch,Ci,Cj,Ck
   real(rp) :: Ch1,Ch4,Ch5          ! Coefficient Ch1,Ch4,Ch5
   real(rp) :: Cl,Cm,Cn,Co,Cp       ! Coefficient Cl,Cm,Cn,Co,Cp  
   real(rp), dimension(msh%ncs+4) :: cr,cs,ct ! Coefficient Cr, Cs, Ct
   
   ! Definition of G coefficients
   real(rp), dimension(msh%ncs+4) :: Gaj,Gbj,Gcj ! Coefficient Gaj,Gbj,Gcj 
   real(rp), dimension(msh%ncs+4) :: Gdj,Gej,Gfj ! Coefficient Gdj,Gej,Gfj 

   ! Useful computation
   real(rp) :: dx,dpdx             ! Spatial step size and inverse of spatial step size
   
   ! Physical parameters
   real(rp), dimension(msh%ncs+4) :: q         ! Discharge
   real(rp), dimension(2) :: qlat      ! Lateral discharge at x and x+1
   real(rp), dimension(2) :: qlatnext  ! Lateral discharge at x and x+1, at t+1
   real(rp), dimension(msh%ncs+4) :: z         ! Water elevation
   real(rp), dimension(msh%ncs+4) :: w         ! Water surface width 
   real(rp), dimension(msh%ncs+4) :: perimeter ! Wet Perimeter 
   real(rp), dimension(msh%ncs+4) :: dPdZ      ! dPdZ
   real(rp), dimension(msh%ncs+4) :: dKdZ      ! dKdZ
   real(rp), dimension(msh%ncs+4) :: rh        ! Hydraulic radius
   real(rp), dimension(msh%ncs+4) :: v         ! Velocity flow
   real(rp), dimension(msh%ncs+4) :: Manning   ! Manning
   real(rp), dimension(msh%ncs+4) :: debitance ! Debitance
   real(rp), dimension(msh%ncs+4) :: zp1       ! New Water elevation
  

!    integer(ip), dimension(msh%ncs+4) :: mVector              ! Pressure for fluxes computing

   real(rp) :: val0, val,conlim,dcldval

   !Function
   real(rp)  :: dPdZFromH
   real(rp)  :: PerimeterFromH
   real(rp)  :: GetWFromH
   real(rp)  :: HtoS

   real(rp)  :: zaval,qaval,temp,temp1,So

   real(rp)  :: coeff,a,fr,b,coeff1,coeff2,frp
      
   real(rp)  :: flow_ratio

   real(rp)  :: frlpi=0.7_rp
   real(rp)  :: mlpi=10.0_rp
   integer(ip) :: i2, iloc, coefnext

   !======================================================================================================================!
   !  Update of data
   !======================================================================================================================!

!    call UpdateMVector(msh,dof,mvector)         ! Update mvector
!    print *, "dof%s(2642)=", dof%s(2642)
!    call SurfaceToHeightCrossSection(msh,dof,1,mvector)          ! Update of dof%h(1)
!    call SurfaceToHeightCrossSection(msh,dof,2,mvector)          ! Update of dof%h(2)
!    call SurfaceToHeightCrossSection(msh,dof,msh%ncs+3,mvector) ! Update of dof%h(msh%ncs+3)
!    call SurfaceToHeightCrossSection(msh,dof,msh%ncs+4,mvector) ! Update of dof%h(msh%ncs+4)
   call update_all_levels(msh, dof%h)         ! Update mvector   
!    call geo_cs_depth_from_area(msh%cs(1), dof%S(1), dof%h(1))
!    call geo_cs_depth_from_area(msh%cs(2), dof%S(2), dof%h(2))
!    call geo_cs_depth_from_area(msh%cs(2), dof%S(2), dof%h(2))

    if ( lat_inflow == '1' ) then
        call compute_qlat(dof)
        iloc=0 !Qlat spatial correspondance counter
    endif
   
!     open(99, file="dh1.txt")
   do ie=3,msh%ncs+2
   
      q(ie)         = dof%q(ie)                             ! Update of q
      z(ie)         = dof%h(ie)+bathy_cell(ie)              ! Update of water elevation
      dof%s(ie)     = HtoS(msh,ie,dof%h(ie))               ! Update of wet surface
      w(ie)         = GetWFromH(msh,dof%h(ie),ie)          ! Update of water surface width 
      perimeter(ie) = PerimeterFromH(msh,dof%h(ie),ie,mvector)     ! Update of Wet Perimeter
      dPdZ(ie)      = min(100.0_rp, dPdZFromH(msh,dof%h(ie),ie,mvector))     ! Update of dPdZ
!       if (perimeter(ie) < 1e-2) print *, ie, dof%s(ie), perimeter(ie), dof%h(ie)

      ! Check-up
      if (perimeter(ie) < -1e-12_rp .or. dof%s(ie) < -1e-12) then
        run_status = -1
        return
      end if

      rh(ie)        = dof%s(ie)/perimeter(ie)               ! Update of Hydraulic radius
      v(ie)         = dof%q(ie)/dof%s(ie)                   ! Update of speed flow
      
      
      ! Check-up !!!
#ifdef EXT_CHECKS   
      if (dof%s(ie) < 1e-12_rp) then
        print *, "S ~= 0 !!", ie, dof%s(ie)
        read(*,*)
      end if
#endif   
      
!       if (rh(ie) < 0.0) then
!         print *, "rh<0", rh(ie), ie, dof%s(ie)
!         print *, perimeter(ie), dof%s(ie), dof%h(ie), mvector(ie)
!       end if
!     write(99,*) dof%q(ie), z(ie), bathy_cell(ie)
   end do
   call calc_K_everywhere(dof, msh, Manning,mvector)                      ! Update of Manning
   call calc_dKdh_everywhere(dof, msh, dKdZ, mvector)
   do ie=3,msh%ncs+2
#ifdef EXT_CHECKS   
      if(Manning(ie) < 5.0 .or. Manning(ie) > 60.0) then
        print *, "Manning out of physical range !!!!!", Manning(ie)
      end if
#endif
      debitance(ie) = Manning(ie)*dof%s(ie)*(rh(ie)**(d2p3))  ! Update of debitance
   end do
!     close(99)

   perimeter(1)=perimeter(3)
   perimeter(2)=perimeter(3)

   perimeter(msh%ncs+3)=perimeter(msh%ncs+2)
   perimeter(msh%ncs+4)=perimeter(msh%ncs+2)

   z(1)=bathy_cell(1)+dof%h(3)
   z(2)=bathy_cell(2)+dof%h(3)

   z(msh%ncs+3)=bathy_cell(msh%ncs+3)+dof%h(msh%ncs+2)
   z(msh%ncs+4)=bathy_cell(msh%ncs+4)+dof%h(msh%ncs+2)

   ! K.Larnier -> Code 0.55 Thesis 2./3
   ! H.Roux    -> Code 2./3 Thesis 0.55
!    sigma= 0.55_rp !(2.0_rp/3.0_rp) 
   sigma= 0.9_rp !(2.0_rp/3.0_rp) 
   sigma= theta_preissmann !(2.0_rp/3.0_rp) 



   call calc_boundary_state( msh,dof)
   
   call UpdateMVector(msh,dof,mvector)                 ! Update mvector   
!    call pressureSgUpdate(msh,dof,mvector,pressureSg)   ! Update pressure

   call SurfaceToHeightCrossSection(msh,dof,1,mvector)          ! Update of dof%h(1)
   call SurfaceToHeightCrossSection(msh,dof,2,mvector)          ! Update of dof%h(2)
   call SurfaceToHeightCrossSection(msh,dof,msh%ncs+3,mvector) ! Update of dof%h(msh%ncs+3)
   call SurfaceToHeightCrossSection(msh,dof,msh%ncs+4,mvector) ! Update of dof%h(msh%ncs+4)
   
   
   !======================================================================================================================!
   !  Cr0,Cs0,Ct0 computing
   !======================================================================================================================!
   Cr(3)=1._rp
   Cs(3)=0._rp
   if (bc%typehyd=='file_FS') then
      Ct(3)=-dof%q(3)+Fourier_Serie( tc,bc%hyd_FS%a0,bc%hyd_FS%n, bc%hyd_FS%A, bc%hyd_FS%B) !( bc%hyd%t ,bc%hyd%q ,tc)
   else if (bc%typehyd=='file') then
      Ct(3)=-dof%q(3)+ linear_interp( bc%hyd%t ,bc%hyd%q ,tc)
!       print *, tc, ts, linear_interp( bc%hyd%t ,bc%hyd%q ,tc)
   else
      Ct(3)=-dof%q(3)+ inflow_user(msh%cs(1)%coord%x,msh%cs(1)%coord%y,tc)
   end if


   !======================================================================================================================!
   !  Ga,Gb,Gc,Gd,Gd,Ge,Gf computing and Cr,Cs,Ct computing
   !======================================================================================================================!

   Cg=sigma ! CG
   Ci=sigma ! CI

   do ie=3,msh%ncs+1

      !Froude computation
! MODIF 1 : Real Froude !
!       fr=abs(v(ie)/sqrt(g*dof%h(ie)))
!       frp=abs(v(ie+1)/sqrt(g*dof%h(ie+1)))
      fr=sqrt(dof%q(ie)**2 * w(ie) / (g * dof%s(ie)**3))
      frp=sqrt(dof%q(ie+1)**2 * w(ie+1) / (g * dof%s(ie+1)**3))

      ! Computation of LPI coefficient at point ie
      if (fr.lt.frlpi) then
         coeff1=1.0_rp-(fr/frlpi)**mlpi
      else
         coeff1=0.0_rp
      endif
!       coeff1 = 1.0_rp

      !Ce
      Ce2   = coeff1*(1._rp)/(2._rp*dt)
      Ce3   = coeff1*(1._rp)/(2._rp*dt)

      ! Computation of LPI coefficient at point ie and ie+1
      if (frp.lt.frlpi) then
         coeff2=1.0_rp-(frp/frlpi)**mlpi
      else
         coeff2=0.0_rp
      endif

      if (coeff2.lt.coeff1) then
         coeff=coeff2
      else
         coeff=coeff1
      endif
#ifdef DEBUG_L3
      print *, "FROUDE(", ie-2, ")=", fr, frp, coeff
      print *, "1:", dof%q(ie), w(ie), dof%s(ie), dof%h(ie) + bathy_cell(ie)
      print *, "2:", dof%q(ie+1), w(ie+1), dof%s(ie+1), dof%h(ie+1) + bathy_cell(ie+1)
#endif
      
      
      dx    = msh%cs(ie+1)%deltademi
      dpdx = (1._rp)/dx
      Ch    =  (dx/(4._rp*dt))*(w(ie+1)+w(ie)) 
      Cj    = -(dx/(4._rp*dt))*(w(ie+1)+w(ie))                            
      Ck    = -(q(ie+1)-q(ie))       

      !CB
      Cb1   = demi*(Q(ie+1)*abs(Q(ie+1))+Q(ie)*abs(Q(ie))) 
      Cb2   = sigma*abs(Q(ie+1))                      
      Cb3   = sigma*abs(Q(ie))                                
      
      !CC
      Cc1   = demi*(debitance(ie+1)*debitance(ie+1)+debitance(ie)*debitance(ie)) 

!       Cc4   = sigma*debitance(ie+1)*d1p3*(Manning(ie+1)*Rh(ie+1)**d2p3)*&
!               (5._rp*w(ie+1)-2._rp*Rh(ie+1)*dPdZ(ie+1))
!       Cc5   = sigma*debitance(ie  )*d1p3*(Manning(ie  )*Rh(ie  )**d2p3)*&
!               (5._rp*w(ie  )-2._rp*Rh(ie  )*dPdZ(ie))
      Cc4   = sigma*debitance(ie+1)*(dKdZ(ie+1)*dof%S(ie+1)*Rh(ie+1)**d2p3 + &
                                     d1p3*(Manning(ie+1)*Rh(ie+1)**d2p3)*(5._rp*w(ie+1)-2._rp*Rh(ie+1)*dPdZ(ie+1)))
      Cc5   = sigma*debitance(ie  )*(dKdZ(ie)*dof%S(ie)*Rh(ie)**d2p3 + &
                                     d1p3*(Manning(ie  )*Rh(ie  )**d2p3)*(5._rp*w(ie  )-2._rp*Rh(ie  )*dPdZ(ie)))

      !CD
      Cd1   = dpdx*(z(ie+1)-z(ie))
      Cd4   =  sigma*dpdx
      Cd5   = -sigma*dpdx

      !CF
      Cf1   =  coeff*dpdx*(q(ie+1)*v(ie+1)-q(ie)*v(ie))
      Cf2   =  coeff*dpdx*2._rp*sigma*v(ie+1)
      Cf3   = -coeff*dpdx*2._rp*sigma*v(ie  )
      Cf4   = -coeff*dpdx*sigma*v(ie+1)*v(ie+1)*w(ie+1)
      Cf5   = -coeff*dpdx*sigma*v(ie  )*v(ie  )*w(ie  )

      !CH
      Ch1   = (1._rp/(2._rp*g))*((1._rp/dof%s(ie+1))+(1._rp/dof%s(ie)))
      Ch4   = - demi*((w(ie+1)*sigma)/(g*dof%s(ie+1)*dof%s(ie+1))) !(w(ie+1)/(dof%s(ie+1)*dof%s(ie+1)))
      Ch5   = - demi*((w(ie  )*sigma)/(g*dof%s(ie  )*dof%s(ie  )))

            !Clat
     select case(lat_inflow)
       case ('1')

       if ( ANY( bc%hyd_lat%loc == ie ) ) then
            iloc=iloc+1
            qlat(1)      = dof%qlat(1,iloc)                          ! Update of qlat
            qlatnext(1)  = dof%qlat(2,iloc)                        ! Update of qlat t+1
            
            
            qlat(2)      = 0.0_rp
            qlatnext(2)  = 0.0_rp
            coefnext=1
            if (iloc < size(bc%hyd_lat%loc)) then
               if ( bc%hyd_lat%loc(iloc+1) == ie+1 ) then
                  qlat(2)      = dof%qlat(1,iloc+1)                          ! Update of qlat x+1
                  qlatnext(2)  = dof%qlat(2,iloc+1)                      ! Update of qlat x+1, t+1
                  coefnext=2
               endif
            endif

! 
!       !!!Mass conservation
        Ck    = Ck + sigma * ( qlatnext(2) + qlatnext(1) )/coefnext + ( 1 - sigma ) * ( qlat(2) + qlat(1) )/coefnext
! 	!!!Momentum conservation
! 	
 	flow_ratio = 0.1 ! To discretize later : speed_ratio = Qlat/(Q+Qlat)
! 	
! 	!!If ulat is given    
 	!Clat1 = sigma/2*(ulatnext(ie+1)+qlatnext(ie)) + (1-sigma)/2*(qlat(ie+1)+qlat(ie))
 	Clat2 = ( sigma / coefnext * ( qlatnext(2) + qlatnext(1) ) + ( 1 - sigma ) / coefnext * ( qlat(2) + qlat(1) ) ) * flow_ratio
 	!Cp    = -(Cb1+Cc1*(Cd1+Ch1*(Cf1-Clat1*Clat2)))
! 	
! 	!!If ulat is a function of Q and S
 	Cl1 =  coeff * (q(ie+1) / dof%s(ie+1) - q(ie) / dof%s(ie) ) / 2
 	Cl2 =  coeff * sigma / 2 / dof%s(ie+1)
 	Cl3 = -coeff * sigma / 2 / dof%s(ie)
 	Cl4 = -coeff * sigma / 2 * w(ie+1) * v(ie+1) / dof%s(ie+1)
 	Cl5 =  coeff * sigma / 2 * w(ie  ) * v(ie  ) / dof%s(ie)
! 
 	Cf1 = Cf1 - Cl1*Clat2
 	Cf2 = Cf2 - Cl2*Clat2
 	Cf3 = Cf3 - Cl3*Clat2
 	Cf4 = Cf4 - Cl4*Clat2
 	Cf5 = Cf5 - Cl5*Clat2
! 
! 
       end if
     end select  
      
      
      
      
      !CL, CM, CN, CO, CP
      Cl    = Cb2+Cc1*Ch1*(Ce2+Cf2)
      Cm    = Cc4*(Cd1+Ch1*Cf1)+Cc1*(Cd4+Ch1*Cf4+Ch4*Cf1)
      Cn    = -(Cb3+CC1*CH1*(Ce3+Cf3))
      Co    = -(Cc5*(Cd1+Ch1*Cf1)+Cc1*(Cd5+Ch1*Cf5+Ch5*Cf1))
      Cp    = -(Cb1+Cc1*(Cd1+Ch1*Cf1))
#ifdef DEBUG_L3
    print *, "C:", Cg, Ch, Ci, Cj, Ck
    print *, "M-I:", Cb2, Cb3, Cb1
    print *, "M-II:", Cc4, Cc5, Cc1
    print *, "M-III:", Cd4, Cd5, Cd1
    print *, "M-IV:", Ch4, Ch5, Ch1
    print *, "M-V:", Ce2, Ce3
    print *, "M-VI:", Cf2, Cf4, Cf3, Cf5, Cf1
    print *, "M:", Cl, Cm, Cn, Co, Cp
!     read(*,*)
#endif

      !Gaj, Gbj, Gc, Gdj, Gej, Gfj
      Gaj(ie)= ( Cl*Cj-Co*Cg)/(Cn*Cj-Co*Ci)
      Gbj(ie)= ( Cm*Cj-Co*Ch)/(Cn*CJ-Co*Ci)
      Gcj(ie)= (-Cp*Cj+Co*Ck)/(Cn*CJ-Co*Ci)
      Gdj(ie)= ( Cl*Ci-Cn*Cg)/(Co*Ci-Cn*Cj)
      Gej(ie)= ( Cm*Ci-Cn*Ch)/(Co*Ci-Cn*Cj)
      Gfj(ie)= (-Cp*Ci+Cn*Ck)/(Co*Ci-Cn*Cj)
      
      !Cr, Cs and Ct coefficients computing
      Cr(ie+1) = cr(ie)*Gaj(ie)+Cs(ie)*Gdj(ie)
      Cs(ie+1) = cr(ie)*Gbj(ie)+Cs(ie)*Gej(ie)
      Ct(ie+1) = ct(ie)-(Cr(ie)*Gcj(ie)+Cs(ie)*Gfj(ie))
      if (abs(Cr(ie+1)) > 1e-02) then
        Cs(ie+1) = Cs(ie+1) / Cr(ie+1)
        Ct(ie+1) = Ct(ie+1) / Cr(ie+1)
        Cr(ie+1) = 1.0_rp
      end if
      
#ifdef DEBUG_L3
      print *, "I:", Cr(ie+1), Cs(ie+1), Ct(ie+1)
      print *, "I3++", Gcj(ie), Gfj(ie)
      print *, "J:", Gdj(ie), Gej(ie), Gfj(ie)
      read(*,*)
#endif

   end do


   !===================================================================================================================!
   !  Computing of Q^{n+1}_{N} and H^{n+1}_{N}
   !===================================================================================================================!

   if (BC_E == 'elevation') then
   
      qaval = dof%q (ie)
      zp1(ie) = dof%h(ie) + bathy_cell(ie)
!       write(199, *) tc, dof%h(ie) + bathy_cell(ie)
      dof%q(ie) = (Ct(ie) - Cs(ie) * (zp1(ie) - z(ie))) / Cr(ie) + qaval
!       print *, "DZ(out)=", zp1(ie) - z(ie)
!       print *, "DQ(out)=", dof%q(ie) - qaval
!       read(*,*)
   
   else if (BC_E == 'normal_depth' .or. BC_E == "neumann") then
   
      qaval = dof%q (ie)
      zaval=z    (ie)
        ! Bottom slope
        So = max(1e-8, (bathy_cell(ie) - bathy_cell(ie+1)) / msh%cs(ie+1)%deltademi)
        ! Surface slope
!         So = max(1e-8, (dof%h(ie-1) + bathy_cell(ie-1) - (dof%h(ie) + bathy_cell(ie))) / msh%cs(ie)%deltademi)
!         call calc_dK_dh(msh, dof, dKdZ, ie, mvector)
!         dKdZ = min(5.0, dKdZ)
        val0 = (dKdZ(ie) * dof%s(ie) * Rh(ie)**d2p3 + Manning(ie)*Rh(ie)**d2p3*d1p3*(5._rp*w(ie)-2._rp*Rh(ie)*dPdZ(ie))) * sqrt(So)
        zp1(ie) = zaval + ct(msh%ncs+2) / (cr(msh%ncs+2) * val0 + cs(msh%ncs+2))
        dof%q(ie) = qaval + val0 * (zp1(ie) - zaval)
!         call UpdateMVectorElement(msh, dof, ie, mvector)
!         perimeter(ie) = PerimeterFromH(msh, zp1(ie)-bathy_cell(ie), ie, mvector)
!         rh(ie)        = HtoS( msh,ie, dof%h(ie) )/perimeter(ie)
!         zaval = zp1(ie)
!         qaval = dof%q (ie)
! !         call calc_K_everywhere(dof, msh, Manning,mvector)
! !         print *, "Q/Q=", dof%q(ie), Manning(ie)*Rh(ie)**d2p3*HtoS( msh,ie, dof%h(ie) ) * sqrt(So)
!   !       if (tc >= 21167999) then 
! !       end do
! !       print *, "dz=", ct(msh%ncs+2) / (cr(msh%ncs+2) * val0 + cs(msh%ncs+2))
! !       print *, "dQ=", val0 * (zp1(ie) - zaval), tc
! !       call UpdateMVectorElement(msh, dof, ie, mvector)
! !       perimeter(ie) = PerimeterFromH(msh, zp1(ie)-bathy_cell(ie), ie, mvector)
! !       rh(ie)        = HtoS( msh,ie, dof%h(ie) )/perimeter(ie)
!       print *, "Q/Q=", dof%q(ie), Manning(ie)*Rh(ie)**d2p3*HtoS( msh,ie, dof%h(ie) ) * sqrt(So), &
!             (dof%q(ie) - Manning(ie)*Rh(ie)**d2p3*HtoS( msh,ie, dof%h(ie) ) * sqrt(So)) / dof%q(ie)
! !       if (ct(msh%ncs+2) / (cr(msh%ncs+2) * val0 + cs(msh%ncs+2)) < -1.0) read(*,*)
! !       if (zp1(ie) < bathy_cell(ie) + 1.0) read(*,*)
!       if (abs((dof%q(ie) - Manning(ie)*Rh(ie)**d2p3*HtoS( msh,ie, dof%h(ie) ) * sqrt(So)) / dof%q(ie)) > 0.01) read(*,*)
!       end if
!       dof%h(ie) = zp1(ie)-bathy_cell(ie)
!       dof%s(ie)   =HtoS( msh,ie, dof%h(ie) )
      
   else if (BC_E == 'ratcurve') then
      if (bc%typerat=='file') then
      
          !Newton
          ie=msh%ncs+2
          val0=q(ie)
          qaval=dof%q(ie)
          zaval=z    (ie)
          val =val0+0.1_rp
          temp=1._rp
          temp1=0.000001
          do i=1,50
              conlim=cr(msh%ncs+2)*(val0-dof%q(msh%ncs+2))+cs(msh%ncs+2)*&
              (linear_interp( bc%rat%q ,bc%rat%h ,val0)-(dof%h(msh%ncs+2)+bathy_cell(msh%ncs+2)))-ct(msh%ncs+2)
              dcldval=cr(msh%ncs+2)+cs(msh%ncs+2)*((linear_interp( bc%rat%q ,bc%rat%h ,val0+1.0)&
              -linear_interp( bc%rat%q ,bc%rat%h ,val0-1.0))/(2.0))
              val=val0
!               if (dabs(conlim/dcldval) > 30.0) then
!                 val0=val0-sign(30.0_rp, conlim/dcldval)
!               else
!                 val0=val0-conlim/dcldval
!               end if
              val0=val0-conlim/dcldval
!               print '(4(E12.5,1X))', val0, val, conlim, dcldval
!               print '(3(A,E12.5))', "Q", val0, ", Z", linear_interp( bc%rat%q ,bc%rat%h ,val0), ", F", conlim
!               read(*,*)
              if (abs(val-val0)<temp1) exit
           end do
           
          dof%q (ie) = val0
          zp1   (ie) =linear_interp( bc%rat%q ,bc%rat%h ,val0)  
!           open(499, file="fort.499", position="append")
!           write(499, *) val0, zp1(ie)
!           close(499)
!           print *, "pause!"
!           read(*,*)
          
!           print *, "C*:", cr(msh%ncs+2), cs(msh%ncs+2), ct(msh%ncs+2)
!           print *, "DQ/Z:", val0-q(ie), zp1(ie) - z(ie)
!           if (zp1(ie) > 179) then
!             print *, "Q(N):", dof%q(ie), q(ie)
!             print *, "Z(N)", zp1(ie), zaval; 
!             print *, "Q(N-1)", q(ie-1)
!             print *, "conlim:", conlim
!             read(*,*)
!             
!             do i = 1, 100
!               val0 = 10.0 + (dof%q(ie) - 10.0) * dble(i) * 0.01
!               conlim=cr(msh%ncs+2)*(val0-qaval)+cs(msh%ncs+2)*&
!               (linear_interp( bc%rat%q ,bc%rat%h ,val0)-(dof%h(msh%ncs+2)+bathy_cell(msh%ncs+2)))-ct(msh%ncs+2)
!               print *, i, val0, conlim
!             end do
!             
!             open(1236, file="res/temp.dat")
!             do i = 3, msh%ncs+2
!               write(1236, '(E12.5,2(51X, E12.5))') msh%cs(i)%coord%x, q(i), dof%h(i)
!             end do
!             close(1236)
!             print *, "res/temp.dat written !"
!             read(*,*)
!             
!           end if

      else if (alpha_ratcurve >= 0.0) then
          qaval = dof%q (ie)
          zaval=z    (ie)
          val0 = alpha_ratcurve * beta_ratcurve * dof%q (ie)**(beta_ratcurve - 1.0_rp)
          dof%q(ie) = qaval + ct(msh%ncs+2) / (cr(msh%ncs+2) + cs(msh%ncs+2) * val0)
          zp1(ie) = zaval + val0 * (dof%q(ie) - qaval)
#ifdef DEBUG_L3
          print *, "parametrized ratcurve:", qaval, zaval, zp1(ie), dof%q(ie)
          print *, "++", val0, qaval, alpha_ratcurve * beta_ratcurve, qaval**(beta_ratcurve - 1.0_rp)
          print *, "++", dof%q(ie)-qaval, Cr(ie),Cs(ie),ct(ie)
#endif

      end if
   end if
   
   dof%h(ie) = max(heps, zp1(ie)-bathy_cell(ie))
   dof%s(ie) = HtoS( msh,ie, dof%h(ie) )

   !===================================================================================================================!
   !  upwindings
   !===================================================================================================================!
#ifdef DEBUG_L3
   print *, msh%ncs-1, dof%q(ie)-qaval, dof%q(ie)
!    read(*,*)
#endif
     do ie=msh%ncs+1,3,-1
      zp1(ie)     = Gdj(ie)*(dof%q(ie+1)-q(ie+1)) +Gej(ie)*(zp1(ie+1)-z(ie+1)) + Gfj(ie) +z(ie)
      dof%q(ie)   = (Ct(ie)-Cs(ie)*(zp1(ie)-z(ie)))/cr(ie) +q(ie)
#ifdef DEBUG_L3
      print *, ie-2, (Ct(ie)-Cs(ie)*(zp1(ie)-z(ie)))/cr(ie), dof%q(ie)
      print *, "++", Ct(ie),Cs(ie),(zp1(ie)-z(ie)),cr(ie)
      print *, "--", Gdj(ie),(dof%q(ie+1)-q(ie+1)),Gej(ie),(zp1(ie+1)-z(ie+1)),Gfj(ie)
!       read(*,*)
#endif

#ifdef DEBUG_L3
      if(zp1(ie)-bathy_cell(ie) < heps) then
        print *, "h < heps !!!!!", ie, zp1(ie)-bathy_cell(ie)
      end if
      if(zp1(ie)-bathy_cell(ie) > 1000.0) then
        print *, "h > 1000.0 !!!!!", ie, zp1(ie)-bathy_cell(ie)
      end if
#endif


      dof%h(ie)   = max(heps, zp1(ie)-bathy_cell(ie))
      !<NOADJ
!       if (dof%h(ie)>1000.0 ) then
!         print *, "preissmann::h>>1", dof%h(ie), q(ie), dof%q(ie), bathy_cell(ie), msh%cs(ie)%height(1)
!         open(72, file="bathy_failure.txt")
!         write(72,*) "# X bathy"
!         do i2 = 1, msh%ncs+4
!           write(72,*) msh%cs(i2)%x, bathy_cell(i2)
!         end do
!         close(72)
!         open(72, file="hydrograph_failure.txt")
!         write(72, '(A)') "!===============================================!"
!         write(72, '(A)') "!  Hydrograph                                   !"
!         write(72, '(A)') "!===============================================!"
!         write(72, *) size(bc%hyd%t)
!         do i2 = 1, size(bc%hyd%t)
!           write(72,*) bc%hyd%t(i2), bc%hyd%q(i2)
!         end do
!         close(72)
!         open(72, file="bathy_failure.dat")
!         write(72,*) "# X bathy"
!         do i2 = 3, msh%ncs+2
!           write(72,*) msh%cs(i2)%x, bathy_cell(i2)
!         end do
!         close(72)
!         open(72, file="hydrograph_failure.dat")
!         write(72,*) "# t q"
!         do i2 = 1, size(bc%hyd%t)
!           write(72,*) bc%hyd%t(i2), bc%hyd%q(i2)
!         end do
!         close(72)
!         print *, "Manning:", alpha, beta
!         stop
!       end if
!       if (dof%h(ie)<1e-3 ) then
! !         print *, "preissmann::h<<1"
! !         read(*,*)
!       end if
!       if (isnan(dof%h(ie))) then
!         print *, "preissmann::NaN"
!         read(*,*)
!       end if
      !>NOADJ
      dof%s(ie)   =HtoS( msh,ie, dof%h(ie) )
   end do
#ifdef DEBUG_L3
   read(*,*)
#endif
   
END SUBROUTINE preissmann_double_sweep_LPI
#endif