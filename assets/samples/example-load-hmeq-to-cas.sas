/* ************************************************************************ */
/* Sample code - load HMEQ data to CAS                                      */
/* ************************************************************************ */

cas;
caslib _all_ assign;

data casdata.hmeq(promote=yes);
	set sampsio.hmeq;
run;

cas terminate;