/* alloca.h is needed with Sun's cc */
#include <alloca.h>

/*
 * Convert Perl sub args to C args and pass them to (*func)().
 */
static int
sparc_pray(ax, items, func)
I32 ax;		/* used by the ST() macro */
I32 items;
int (*func)();
{
  STRLEN arg_len, chunk_len;
  char *arg_scalar, *arg_on_stack;
  int nbytes = 0;
  int pseu[6];  /* Array of first six "pseudo-arguments" */
  int check_len;
  register int i, j;
  int stack_needed = 0;

  for (i = DYNALIB_ARGSTART; i < items; ) {
    arg_scalar = SvPV(ST(i), arg_len);
    i++;
    check_len = nbytes + arg_len;
    if (check_len > sizeof pseu) {
      stack_needed = check_len - sizeof pseu;
      arg_len -= stack_needed;
    }
    Copy(arg_scalar, &((char *) (&pseu[0]))[nbytes], arg_len, char);
    nbytes = check_len;
    if (check_len >= sizeof pseu) {
      for (j = i; j < items; j++) {
	SvPV(ST(j), arg_len);
	stack_needed += arg_len;
      }
      if (stack_needed > 0) {
	arg_on_stack = alloca(stack_needed);
	/* Wish I knew why we have to subtract off 4. */
	arg_on_stack -= sizeof (int);
	if (check_len > sizeof pseu) {
	  /* An argument straddles the 6-word line; part goes on stack. */
	  SvPV(ST(i), arg_len);
	  chunk_len = check_len - sizeof pseu;
	  Copy(&arg_scalar[arg_len - chunk_len], arg_on_stack, chunk_len, char);
	  arg_on_stack += chunk_len;
	}
	while (i < items) {
	  arg_scalar = SvPV(ST(i), arg_len);
	  i++;
	  Copy(arg_scalar, arg_on_stack, arg_len, char);
	  arg_on_stack += arg_len;
	}
      }
    }
  }
  /* Cross your fingers. */
  return (*((int (*)()) func))(pseu[0], pseu[1], pseu[2],
			       pseu[3], pseu[4], pseu[5]);
}

#define sparc_CALL(func, type)						\
    ((*((type (*)(I32, I32, void *)) sparc_pray))(ax,items,func))
