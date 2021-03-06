!-----------------------------------------------------------------------------!
!   CP2K: A general program to perform molecular dynamics simulations         !
!   Copyright (C) 2000 - 2011  CP2K developers group                          !
!-----------------------------------------------------------------------------!
 
! *****************************************************************************
!> \brief a module to allow simple internal preprocessing in input files.
!> \par History
!>      - standalone proof-of-concept implementation (20.02.2008,AK)
!>      - integration into cp2k (22.02.2008,tlaino)
!>      - variables added (25.02.2008,AK)
!> \author Axel Kohlmeyer [AK] - CMM/UPenn Philadelphia
!> \date 25.02.2008
! *****************************************************************************
MODULE cp_parser_ilist_types
  USE f77_blas
#include "cp_common_uses.h"

  IMPLICIT NONE
  PRIVATE

  TYPE ilist_type
     LOGICAL                              :: in_use
     INTEGER                              :: nel_list
     INTEGER                              :: istart, iend
     INTEGER                              :: ipresent
  END TYPE ilist_type

  PUBLIC :: ilist_type, create_ilist_type, release_ilist_type
  CHARACTER(len=*), PARAMETER, PRIVATE :: moduleN = 'cp_parser_ilist_types'
  
CONTAINS

! ****************************************************************************
!> \brief creates the integer listing type
!> \author Teodoro Laino [tlaino] - University of Zurich
!> \date  08.2008
! *****************************************************************************
  SUBROUTINE create_ilist_type(ilist, error)
    TYPE(ilist_type), POINTER                :: ilist
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'create_ilist_type', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: stat
    LOGICAL                                  :: failure

    failure = .FALSE.
    CPPostcondition(.NOT.ASSOCIATED(ilist),cp_failure_level,routineP,error,failure)
    ALLOCATE(ilist, stat=stat)
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
    ilist%istart   = HUGE(0)
    ilist%iend     = HUGE(0)
    ilist%nel_list = HUGE(0)    
    ilist%ipresent = HUGE(0)
    ilist%in_use   = .FALSE.

  END SUBROUTINE create_ilist_type

! ****************************************************************************
!> \brief creates the integer listing type
!> \author Teodoro Laino [tlaino] - University of Zurich
!> \date  08.2008
! *****************************************************************************
  SUBROUTINE release_ilist_type(ilist, error)
    TYPE(ilist_type), POINTER                :: ilist
    TYPE(cp_error_type), INTENT(inout)       :: error

    CHARACTER(len=*), PARAMETER :: routineN = 'release_ilist_type', &
      routineP = moduleN//':'//routineN

    INTEGER                                  :: stat
    LOGICAL                                  :: failure

    failure = .FALSE.
    CPPostcondition(ASSOCIATED(ilist),cp_failure_level,routineP,error,failure)
    DEALLOCATE(ilist, stat=stat)
    CPPostcondition(stat==0,cp_failure_level,routineP,error,failure)
  END SUBROUTINE release_ilist_type

END MODULE cp_parser_ilist_types
