/* cdecl.h is generated when you run `perl Makefile.PL DECL=cdecl' */
#include "cdecl.h"

/*
 * Convert Perl sub args to C args and pass them to (*func)().
 */
static int
cdecl_pray(ax, items, func)
I32 ax;		/* used by the ST() macro */
I32 items;
void *func;
{
  STRLEN arg_len;
  char *arg_scalar, *arg_on_stack;
  register int i;
#if CDECL_ONE_BY_ONE

#if CDECL_REVERSE
  for (i = DYNALIB_ARGSTART; i < items; i++) {
#else  /* ! CDECL_REVERSE */
  for (i = items - 1; i >= DYNALIB_ARGSTART; i--) {
#endif  /* ! CDECL_REVERSE */
    arg_scalar = SvPV(ST(i), arg_len);
    arg_on_stack = alloca(arg_len);
    Copy(arg_scalar, arg_on_stack, arg_len, char);
  }
#else  /* ! CDECL_ONE_BY_ONE */
  STRLEN total_arg_len = 0;

  for (i = items; i-- > DYNALIB_ARGSTART; ) {
    (void) SvPV(ST(i), arg_len);
    total_arg_len += arg_len;
  }
  arg_on_stack = (char *) alloca(total_arg_len) + CDECL_ADJUST;
#if CDECL_REVERSE
  for (i = items - 1; i >= DYNALIB_ARGSTART; i--) {
#else  /* ! CDECL_REVERSE */
  for (i = DYNALIB_ARGSTART; i < items; i++) {
#endif  /* ! CDECL_REVERSE */
    arg_scalar = SvPV(ST(i), arg_len);
    Copy(arg_scalar, arg_on_stack, arg_len, char);
    arg_on_stack += arg_len;
  }
#endif  /* ! CDECL_ONE_BY_ONE */

  /* Cross your fingers. */
  return (*((int (*)()) func))();
}

#define cdecl_CALL(func, type)						\
    ((*((type (*)(I32, I32, void *)) cdecl_pray))(ax,items,func))
