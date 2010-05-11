/*
 * This program tries to generate an appropriate header file for
 * inclusion with cdecl.c.
 */

#define main notmain
#include <EXTERN.h>
#include <perl.h>
#undef main
#undef fprintf
#undef fopen
#undef fclose

#include <stdio.h>

#ifdef INCLUDE_ALLOCA
#include <alloca.h>
#endif
#ifdef INCLUDE_MALLOC
#include <malloc.h>
#endif

#ifndef SIGSEGV
#include <signal.h>
#endif

/*          0003709D,0009675A,003ACACB,359C46D6,05261433,
            00FCA2D6,00016FCF,004AA9C6,04A2CD24 */
I32 a[] = { 225437, 616282, 3853003, 899434198, 86381619,
	    16556758, 94159, 4893126, 77778212 };

int grows_downward;
int one_by_one = 1;
int reverse = 0;
int do_reverse = 0;
int args_size[2];
int adjust[] = {0, 0};
int do_adjust = 0;

int *which;

void handler(int sig) {
  printf("abnormal exit 1\n");
  exit(1);
}

int test(b0, b1, b2, b3, b4, b5, b6, b7, b8)
     I32 b0, b1, b2, b3, b4, b5, b6, b7, b8;
{
  int i;

  if (b0 == a[0]
      && b1 == a[1]
      && b2 == a[2]
      && b3 == a[3]
      && b4 == a[4]
      && b5 == a[5]
      && b6 == a[6]
      && b7 == a[7]
      && b8 == a[8]
      ) {
#ifdef VERBOSE
      printf("test ok\n");
#endif
      return 1;
  }
  for (i = 0; i < 9; i++) {
    if (a[i] == b4) {
      if ((i == 0 || a[i-1] == b3) && (i == 8 || a[i+1] == b5)) {
	*which = (i - 4) * sizeof (I32);
	break;
      }
      else if ((i == 0 || a[i-1] == b5) && (i == 8 || a[i+1] == b3)) {
	reverse = 1;
	*which = (i - 4) * sizeof (I32);
	break;
      }
    }
  }
  return 0;
}

int do_one_arg(x)
  char *x;
{
  char *arg;
  int i;

  args_size[0] = sizeof x;
  which = &adjust[0];
  if (one_by_one) {
    for (i = 8; i >= 0; i--) {
      arg = (char *) alloca(sizeof (I32));
      Copy(&a[do_reverse ? 8-i : i], arg, sizeof (I32), char);
    }
  }
  else {
    arg = (char *) alloca(sizeof a) + do_adjust;
    for (i = 0; i < 9; i++) {
      Copy(&a[do_reverse ? 8-i : i], arg, sizeof (I32), char);
      arg += sizeof (I32);
    }
  }
  return ((int (*)()) test)();
}

int do_three_args(x, y, z)
  int x;
  char *y;
  double z;
{
  char *arg;
  int i;

  args_size[1] = sizeof x + sizeof y + sizeof z;
  which = &adjust[1];
  if (one_by_one) {
    for (i = 8; i >= 0; i--) {
      arg = (char *) alloca(sizeof (I32));
      Copy(&a[do_reverse ? 8-i : i], arg, sizeof (I32), char);
    }
  }
  else {
    arg = (char *) alloca(sizeof a) + do_adjust;
    for (i = 0; i < 9; i++) {
      Copy(&a[do_reverse ? 8-i : i], arg, sizeof (I32), char);
      arg += sizeof (I32);
    }
  }
  return ((int (*)()) test)();
}

int main(argc, argv)
  int argc;
  char **argv;
{
  FILE *fp;
  int one_arg, three_args;
  int *p1, *p2;

#ifdef SIGSEGV
  signal(SIGSEGV, handler);
#endif
#ifdef SIGILL
  signal(SIGILL, handler);
#endif
  if (argc > 1) {
    do_adjust = atoi(argv[1]);
  }
  p1 = (int *) alloca(sizeof *p1);
  p2 = (int *) alloca(sizeof *p2); /* p1 - 0x20 */
  grows_downward = (p1 - p2 > 0 ? 1 : 0);
  one_by_one = (p1 - p2 == (grows_downward ? 1 : -1));
#ifdef VERBOSE  
  printf("p1-p2=%d,do_adjust=%d,grows_downward=%d,one_by_one=%d\n",
	 (char*)p1-(char*)p2,do_adjust,grows_downward,one_by_one);
#endif

  /* compute adjust[0] and reverse */
  one_arg = do_one_arg(NULL);
#ifdef VERBOSE
  printf("one_arg=%d,reverse=%d,adjust=[%d,%d]\n",
	 one_arg,reverse,adjust[0],adjust[1]);
#endif
  if (reverse) {
    do_reverse = reverse ^ (one_by_one ? grows_downward : 0);
    /* try with computed adjust[0] and reverse */
    one_arg = do_one_arg(NULL);
#ifdef VERBOSE
    printf("do_reverse=%d,adjust=[%d,%d]\n",
	    do_reverse,adjust[0],adjust[1]);
#endif
  }

  /* verify and compute adjust[1] for more args */
  do_adjust = adjust[0];
  three_args = do_three_args(0, NULL, 0.0);
#ifdef VERBOSE
  printf("three_args=%d,adjust=[%d,%d]\n",three_args,adjust[0],adjust[1]);
#endif
  /* adjust[1] maybe different? */
  if (! one_arg || ! three_args) {
    if (adjust[0] != 0) {
      do_adjust = adjust[0];
      one_arg = do_one_arg(NULL);
      three_args = do_three_args(0, NULL, 0.0);
#ifdef VERBOSE
      printf("do_adjust=%d,one_arg=%d,three_args=%d,adjust=[%d,%d],do_adjust=%d\n",
	     do_adjust,one_arg,three_args,adjust[0],adjust[1],do_adjust);
#endif
    }
  }
  /* try it a last time by forcing adjust to offset */
  if (! one_arg || ! three_args) {
      /*for (do_adjust=-32; do_adjust <=32; do_adjust+=4) {*/
      do_adjust = (char*)p2 - (char*)p1;
      adjust[0] = adjust[1] = do_adjust;
#ifdef VERBOSE
      printf("try adjust=[%d,%d]\n",adjust[0],adjust[1]);
#endif
      one_arg = do_one_arg(NULL);
      three_args = do_three_args(0, NULL, 0.0);
#ifdef VERBOSE
      printf("one_arg=%d,three_args=%d,adjust=[%d,%d],reverse=%d\n",
	     one_arg,three_args,adjust[0],adjust[1],reverse);
#endif
    }
  }
  if (one_arg && three_args) {
    fp = fopen("cdecl.h", "w");
    if (fp == NULL) {
      return 1;
    }
    fprintf(fp, "/*\n"
	    " * cdecl.h -- configuration parameters for the cdecl calling convention\n"
	    " *\n"
	    " * Generated automatically by %s.\n", argv[0]);
#ifndef __FILE__
#define __FILE__ "testcall.c"
#endif
    fprintf(fp, " * Do not edit this file.  Edit %s and/or Makefile.PL instead.\n",
	    __FILE__);
    fprintf(fp, " */\n\n");
#ifdef INCLUDE_ALLOCA
    fprintf(fp, "#include <alloca.h>\n");
#endif
#ifdef INCLUDE_MALLOC
    fprintf(fp, "#include <malloc.h>\n");
#endif
    fprintf(fp, "#define CDECL_ONE_BY_ONE %d\n", one_by_one);
    fprintf(fp, "#define CDECL_ADJUST %d\n", do_adjust);
    fprintf(fp, "#define CDECL_REVERSE %d\n", do_reverse);
    fclose(fp);
    return 0;
  }
#ifdef VERBOSE
  printf("cdecl failed\n");
#endif
  return 1;
}
