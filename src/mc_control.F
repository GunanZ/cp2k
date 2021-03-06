!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!

! *****************************************************************************
!> \brief contains some general routines for dealing with the restart
!>      files and creating force_env for MC use
!> \par History
!>      none
!> \author MJM
! *****************************************************************************
MODULE mc_control
  USE atomic_kind_types,               ONLY: get_atomic_kind
  USE cell_types,                      ONLY: cell_type,&
                                             get_cell
  USE cp_files,                        ONLY: close_file,&
                                             open_file
  USE cp_para_types,                   ONLY: cp_para_env_type
  USE cp_subsys_types,                 ONLY: cp_subsys_get,&
                                             cp_subsys_type
  USE environment,                     ONLY: cp2k_read
  USE f77_blas
  USE fist_main,                       ONLY: fist_create_force_env
  USE force_env_types,                 ONLY: force_env_get,&
                                             force_env_type
  USE global_types,                    ONLY: global_environment_type,&
                                             globenv_create,&
                                             globenv_release
  USE input_constants,                 ONLY: do_fist,&
                                             do_qs
  USE input_cp2k,                      ONLY: create_cp2k_input_reading,&
                                             empty_initial_variables
  USE input_cp2k_check,                ONLY: check_cp2k_input
  USE input_section_types,             ONLY: section_vals_get,&
                                             section_vals_get_subs_vals,&
                                             section_vals_type,&
                                             section_vals_val_get
  USE kinds,                           ONLY: default_path_length,&
                                             default_string_length,&
                                             dp,&
                                             dp_size,&
                                             int_size
  USE mc_misc,                         ONLY: mc_make_dat_file_new
  USE mc_types,                        ONLY: get_mc_molecule_info,&
                                             get_mc_par,&
                                             mc_input_file_type,&
                                             mc_molecule_info_type,&
                                             mc_simpar_type,&
                                             set_mc_par
  USE message_passing,                 ONLY: mp_bcast
  USE mol_kind_new_list_types,         ONLY: mol_kind_new_list_type
  USE molecule_kind_types,             ONLY: atom_type,&
                                             get_molecule_kind,&
                                             molecule_kind_type
  USE parallel_rng_types,              ONLY: next_random_number,&
                                             rng_stream_type
  USE particle_list_types,             ONLY: particle_list_type
  USE physcon,                         ONLY: angstrom
  USE qs_main,                         ONLY: quickstep_create_force_env
  USE termination,                     ONLY: stop_memory,&
                                             stop_program
  USE timings,                         ONLY: timeset,&
                                             timestop
#include "cp_common_uses.h"

  IMPLICIT NONE

  PRIVATE
  ! *** Global parameters ***

  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'mc_control'

  PUBLIC :: write_mc_restart,read_mc_restart,mc_create_force_env,&
       mc_create_bias_force_env

CONTAINS

! *****************************************************************************
!> \brief writes the coordinates of the current step to a file that can
!>      be read in at the start of the next simulation
!> \param mc_par the mc parameters for the force env
!> \param force_env the force environment to write the coords from
!> \param nnstep how many steps the simulation has run
!> 
!>    Only use in serial.
!> \author MJM
! *****************************************************************************
  SUBROUTINE write_mc_restart ( nnstep, mc_par, nchains,force_env )

    INTEGER, INTENT(IN)                      :: nnstep
    TYPE(mc_simpar_type), POINTER            :: mc_par
    INTEGER, DIMENSION(:), INTENT(IN)        :: nchains
    TYPE(force_env_type), POINTER            :: force_env

    CHARACTER(len=*), PARAMETER :: routineN = 'write_mc_restart', &
      routineP = moduleN//':'//routineN

    CHARACTER(LEN=20)                        :: ensemble
    CHARACTER(LEN=default_path_length)       :: restart_file_name
    CHARACTER(LEN=default_string_length)     :: name
    INTEGER                                  :: handle, ichain, imol_type, &
                                                iparticle, iunit, natom, &
                                                nmol_types, nmolecule, &
                                                nunits_tot, unit
    REAL(KIND=dp)                            :: temperature
    REAL(KIND=dp), DIMENSION(1:3)            :: abc
    TYPE(atom_type), DIMENSION(:), POINTER   :: atom_list
    TYPE(cell_type), POINTER                 :: cell
    TYPE(cp_error_type)                      :: error
    TYPE(cp_subsys_type), POINTER            :: subsys
    TYPE(mol_kind_new_list_type), POINTER    :: molecule_kinds_new
    TYPE(molecule_kind_type), POINTER        :: molecule_kind
    TYPE(particle_list_type), POINTER        :: particles

    CALL timeset(routineN,handle)

    ! get some data from mc_par
    CALL get_mc_par(mc_par,restart_file_name=restart_file_name,temperature=temperature,&
         ensemble=ensemble)

    ! open the file and write some simulation parameters
    CALL open_file(file_name=restart_file_name,unit_number=unit,&
         file_action='WRITE',file_status='REPLACE')

    ! get the cell length and coordinates
    CALL force_env_get(force_env,cell=cell,subsys=subsys,&
         error=error)
    CALL get_cell(cell,abc=abc)
    CALL cp_subsys_get(subsys, &
         molecule_kinds_new=molecule_kinds_new,&
         particles=particles, error=error)

    nunits_tot=SIZE(particles%els(:))
    IF(SUM(nchains(:)) == 0) nunits_tot=0
    WRITE(unit,*) nnstep
    WRITE(unit,*) temperature,nunits_tot
    WRITE(unit,*) ensemble
    WRITE(unit,*) nchains(:)
    WRITE(unit,'(3(F10.6,3X))') abc(1:3)*angstrom  ! in angstroms
    WRITE(unit,*)

    ! can't do a simple particles%els%atomic_kind%element_symbol because
    ! of the classical force_env
    IF(nunits_tot .GT. 0) THEN
       nmol_types=SIZE(molecule_kinds_new%els(:))
       iparticle=1
       DO imol_type=1,nmol_types
          molecule_kind => molecule_kinds_new%els(imol_type)
          CALL get_molecule_kind(molecule_kind,atom_list=atom_list,&
               nmolecule=nmolecule,natom=natom)
          ! write the coordinates out
          DO ichain=1,nmolecule
             DO iunit=1,natom
                CALL get_atomic_kind(atom_list(iunit)%atomic_kind, name=name)
                WRITE(unit,'(1X,A,1X,3(F15.10,3X))') &
                     TRIM(ADJUSTL(name)),&
                     particles%els(iparticle)%r(1:3)*angstrom
                iparticle=iparticle+1
             ENDDO
          ENDDO
       ENDDO
    ENDIF

    CALL close_file(unit_number=unit)

    ! end the timing
    CALL timestop(handle)

  END SUBROUTINE write_mc_restart

! *****************************************************************************
!> \brief reads the input coordinates of the simulation from a file written above
!> \param mc_par the mc parameters for the force env
!> \param force_env the force environment to write the coords from
!> \param iw the unit to write an error message to, in case current
!>            simulation parameters don't match what's in the restart file
!> \param rng_stream the stream we pull random numbers from
!> 
!>      Used in parallel.
!> \author MJM
! *****************************************************************************
  SUBROUTINE read_mc_restart ( mc_par, force_env, iw, mc_nunits_tot,rng_stream)

    TYPE(mc_simpar_type), POINTER            :: mc_par
    TYPE(force_env_type), POINTER            :: force_env
    INTEGER, INTENT(IN)                      :: iw
    INTEGER, INTENT(INOUT)                   :: mc_nunits_tot
    TYPE(rng_stream_type), POINTER           :: rng_stream

    CHARACTER(len=*), PARAMETER :: routineN = 'read_mc_restart', &
      routineP = moduleN//':'//routineN

    CHARACTER(5), ALLOCATABLE, DIMENSION(:)  :: atom_symbols
    CHARACTER(default_string_length), &
      DIMENSION(:, :), POINTER               :: atom_names
    CHARACTER(LEN=20)                        :: ensemble, mc_ensemble
    CHARACTER(LEN=default_path_length)       :: dat_file, restart_file_name
    INTEGER                                  :: group, handle, i, ipart, &
                                                istat, iunit, nmol_types, &
                                                nstart, nunits_tot, &
                                                print_level, source, unit
    INTEGER, DIMENSION(:), POINTER           :: nchains, nunits
    LOGICAL                                  :: ionode
    REAL(KIND=dp)                            :: mc_temp, rand, temperature
    REAL(KIND=dp), ALLOCATABLE, &
      DIMENSION(:, :)                        :: r
    REAL(KIND=dp), DIMENSION(1:3)            :: abc, box_length
    TYPE(cell_type), POINTER                 :: cell
    TYPE(cp_error_type)                      :: error
    TYPE(cp_subsys_type), POINTER            :: subsys
    TYPE(mc_input_file_type), POINTER        :: mc_input_file
    TYPE(mc_molecule_info_type), POINTER     :: mc_molecule_info
    TYPE(particle_list_type), POINTER        :: particles

    CALL timeset(routineN,handle)

    ! get some stuff from the mc_par
    CALL get_mc_par(mc_par,restart_file_name=restart_file_name,temperature=mc_temp,&
         ensemble=mc_ensemble,mc_molecule_info=mc_molecule_info,&
         ionode=ionode,dat_file=dat_file,&
         group=group,source=source,mc_input_file=mc_input_file)
    CALL get_mc_molecule_info(mc_molecule_info,nunits=nunits,&
         nmol_types=nmol_types,atom_names=atom_names)

    ALLOCATE (nchains(1:nmol_types),STAT=istat)
    IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
         "nchains",nmol_types*int_size)

    ! currently a hack, printlevel should be intern to the print_keys
    print_level = 1

    IF(ionode) THEN
       ! open the file and read some simulation parameters
       CALL open_file(file_name=restart_file_name,unit_number=unit,&
            file_action='READ',file_status='OLD')

       READ(unit,*) nstart
       READ(unit,*) temperature,nunits_tot
       READ(unit,*) ensemble
       READ(unit,*) nchains(1:nmol_types)
    ENDIF
    CALL mp_bcast(nstart,source,group)
    CALL mp_bcast(temperature,source,group)
    CALL mp_bcast(nunits_tot,source,group)
    CALL mp_bcast(ensemble,source,group)

    ! do some checking
    IF(ABS(temperature - mc_temp) .GT. 0.01E0_dp) THEN
       IF(ionode) THEN
          WRITE(iw,*) 'The temperature in the restart file is ',&
               'not the same as the input file.'
          WRITE(iw,*) 'Input file temperature =',mc_temp
          WRITE(iw,*) 'Restart file temperature =',temperature
       ENDIF
       CALL stop_program(routineN,moduleN,__LINE__,&
            "Temperature difference between restart and input")
    ENDIF
    IF(nunits_tot .NE. mc_nunits_tot) THEN
       IF(ionode) THEN
          WRITE(iw,*) 'The total number of units in the restart ',&
               'file is not the same as the input file.'
          WRITE(iw,*) 'Input file units =',mc_nunits_tot
          WRITE(iw,*) 'Restart file units =',nunits_tot
       ENDIF
       mc_nunits_tot=nunits_tot
    ENDIF
    IF(ensemble .NE. mc_ensemble) THEN
       IF(ionode) THEN
          WRITE(iw,*) 'The ensemble in the restart file is ',&
               'not the same as the input file.'
          WRITE(iw,*) 'Input file ensemble =',mc_ensemble
          WRITE(iw,*) 'Restart file ensemble =',ensemble
       ENDIF
       CALL stop_program(routineN,moduleN,__LINE__,&
            "Ensembles different between restart and input")
    ENDIF

    ! get the cell length and coordinates
    CALL force_env_get(force_env,cell=cell,subsys=subsys,&
         error=error)
    CALL get_cell(cell,abc=abc)
    CALL cp_subsys_get(subsys, &
         particles=particles, error=error)

    IF(ionode) THEN
       READ(unit,*)  box_length(1:3) ! in angstroms
       READ(unit,*)
       box_length(1:3)=box_length(1:3)/angstrom ! convert to a.u.
    ENDIF
    CALL mp_bcast(box_length,source,group)
    IF(ABS(box_length(1) - abc(1)) .GT. 0.0001E0_dp .OR. &
         ABS(box_length(2) - abc(2)) .GT. 0.0001E0_dp .OR. &
         ABS(box_length(3) - abc(3)) .GT. 0.0001E0_dp) THEN
       IF (ionode) THEN
          WRITE(iw,*) 'The cell length in the restart file is ',&
               'not the same as the input file.'
          WRITE(iw,*) 'Input file cell length =',abc(1:3)*angstrom
          WRITE(iw,*) 'Restart file cell length =',box_length(1:3)*angstrom
       ENDIF
    ENDIF

    ! allocate the array holding the coordiantes, and read in the coordiantes,
    ! and write the dat file so we can make a new force_env
    IF(SUM(nchains(:)) == 0) THEN
       ALLOCATE (r(3,nunits(1)),STAT=istat)
       IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
            "r",3*nunits(1)*dp_size)
       ALLOCATE (atom_symbols(nunits(1)),STAT=istat)
       IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
            "ipart",nunits_tot*5)

       DO iunit=1,nunits(1)
          r(1:3,iunit) = (/ REAL(iunit,dp), REAL(iunit,dp),REAL(iunit,dp) /)
          atom_symbols(iunit)=atom_names(iunit,1)
       ENDDO

       IF(ionode) THEN
          CALL mc_make_dat_file_new(r(:,:),atom_symbols,0,&
               box_length(:),dat_file,nchains(:),mc_input_file)
          CALL close_file(unit_number=unit)
       ENDIF
    ELSE
       ALLOCATE (r(3,nunits_tot),STAT=istat)
       IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
            "r",3*nunits_tot*dp_size)
       ALLOCATE (atom_symbols(nunits_tot),STAT=istat)
       IF (istat /= 0) CALL stop_memory(routineN,moduleN,__LINE__,&
            "ipart",nunits_tot*5)

       IF(ionode) THEN
          DO ipart=1,nunits_tot
             READ(unit,*) atom_symbols(ipart),r(1:3,ipart)
             r(1:3,ipart)=r(1:3,ipart)/angstrom
          ENDDO

          CALL close_file(unit_number=unit)

          CALL mc_make_dat_file_new(r(:,:),atom_symbols,nunits_tot,&
               box_length(:),dat_file,nchains(:),mc_input_file)

       ENDIF
    ENDIF

    CALL set_mc_par(mc_par,nstart=nstart)

    ! advance the random number sequence based on the restart step
    IF(ionode) THEN
       DO i=1,nstart+1
          rand=next_random_number(rng_stream,error=error)
       ENDDO
    ENDIF

    ! end the timing
    CALL timestop(handle)

    ! deallcoate
    DEALLOCATE(nchains)
    DEALLOCATE(r)
    DEALLOCATE(atom_symbols)

  END SUBROUTINE read_mc_restart

! *****************************************************************************
!> \brief creates a force environment for any of the different kinds of
!>      MC simulations we can do (FIST, QS)
!> \param force_env the force environment to create
!> \param globenv the global environment parameters
!> \param error the CP error structure
!> 
!>    Suitable for parallel.
!> \author MJM
! *****************************************************************************
  SUBROUTINE mc_create_force_env ( force_env, para_env, input_file_name,&
       globenv_new, error )

    TYPE(force_env_type), POINTER            :: force_env
    TYPE(cp_para_env_type), POINTER          :: para_env
    CHARACTER(LEN=*), INTENT(IN)             :: input_file_name
    TYPE(global_environment_type), &
      OPTIONAL, POINTER                      :: globenv_new
    TYPE(cp_error_type), INTENT(INOUT)       :: error

    CHARACTER(LEN=*), PARAMETER :: routineN = 'mc_create_force_env', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: method_name_id, nforce_eval
    LOGICAL                                  :: failure
    TYPE(global_environment_type), POINTER   :: globenv
    TYPE(section_vals_type), POINTER         :: force_env_section, &
                                                root_section, subsys_section

    failure= .FALSE.
    NULLIFY(globenv, force_env, force_env_section, subsys_section )

    ! init globenv with the data
    CALL globenv_create(globenv, error=error)

    ! parse the input
    root_section => create_cp2k_input_reading(input_file_name,initial_variables=empty_initial_variables,&
                                              para_env=para_env,error=error)
    ! it has been a problem that the .dat file is written incorrectly...
    ! this will help check that
    CPAssert(cp_error_get_level(error)<=CP_WARNING_LEVEL,cp_failure_level,routineP,error,failure)

    CALL check_cp2k_input(root_section,para_env=para_env,error=error)

    CALL cp2k_read(root_section,para_env,globenv,error=error)
    force_env_section => section_vals_get_subs_vals(root_section,"FORCE_EVAL",error=error)
    CALL section_vals_val_get(root_section,"GLOBAL%PROGRAM_NAME",i_val=globenv%prog_name_id,error=error)
    CALL section_vals_val_get(force_env_section,"METHOD",i_val=method_name_id,error=error)
    CALL section_vals_get(force_env_section, n_repetition=nforce_eval, error=error)

    CPAssert(nforce_eval==1,cp_failure_level,routineP,error,failure)
    SELECT CASE ( method_name_id )
    CASE ( do_fist )
       CALL fist_create_force_env(force_env, root_section, para_env, globenv,&
            force_env_section=force_env_section, subsys_section=subsys_section,&
            use_motion_section=.TRUE., error=error)

    CASE ( do_qs )
       CALL quickstep_create_force_env(force_env, root_section,  para_env,globenv, &
            force_env_section=force_env_section, subsys_section=subsys_section,&
            use_motion_section=.TRUE., error=error)
    CASE default
       CPAssert(.FALSE.,cp_failure_level,routineP,error,failure)
    END SELECT

    IF(PRESENT(globenv_new))THEN
       globenv_new => globenv
    ELSE
       CALL globenv_release(globenv,error)
    ENDIF

  END SUBROUTINE mc_create_force_env

! *****************************************************************************
!> \brief essentially copies the cell size and coordinates of one force env
!>      to another that we will use to bias some moves with
!> \param bias_env the force environment to create
!> \param force_env the force environment we're copying cell length
!>            and coordinates from
!> \param globenv the global environment parameters
!> \param error the CP error structure
!> 
!>    Suitable for parallel.
!> \author MJM
! *****************************************************************************
  SUBROUTINE mc_create_bias_force_env (bias_env,r,atom_symbols,nunits_tot,&
       para_env, box_length,nchains,mc_input_file,ionode,error)

    TYPE(force_env_type), POINTER            :: bias_env
    REAL(dp), DIMENSION(:, :), INTENT(INOUT) :: r
    CHARACTER(default_string_length), &
      DIMENSION(:), INTENT(IN)               :: atom_symbols
    INTEGER, INTENT(IN)                      :: nunits_tot
    TYPE(cp_para_env_type), POINTER          :: para_env
    REAL(KIND=dp), DIMENSION(1:3), &
      INTENT(IN)                             :: box_length
    INTEGER, DIMENSION(:), POINTER           :: nchains
    TYPE(mc_input_file_type), POINTER        :: mc_input_file
    LOGICAL, INTENT(IN)                      :: ionode
    TYPE(cp_error_type), INTENT(INOUT)       :: error

    CHARACTER(LEN=*), PARAMETER :: routineN = 'mc_create_bias_force_env', &
      routineP = moduleN//':'//routineN

    IF(ionode) &
         CALL mc_make_dat_file_new(r(:,:),atom_symbols,nunits_tot,&
         box_length(:),'bias_temp.dat',nchains(:),mc_input_file)

    CALL mc_create_force_env(bias_env, para_env, 'bias_temp.dat',error=error)

  END SUBROUTINE mc_create_bias_force_env

END MODULE mc_control

