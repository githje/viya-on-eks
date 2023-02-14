/* ************************************************************************ */
/* Sample code - load HMEQ data to CAS                                      */
/* ************************************************************************ */

cas;
caslib _all_ assign;

data public.hmeq(promote=yes);
	set sampsio.hmeq;
run;

cas terminate;