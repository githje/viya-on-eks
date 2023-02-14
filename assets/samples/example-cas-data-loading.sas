/* ************************************************************************ */
/* Sample code - create a libname statement pointing to shared storage      */
/* ************************************************************************ */

/* Note: this SAS libname uses persistent storage outside the Kubernetes
 * cluster (/shared). You can transfer data to and from this folder using 
 * the filebrowser web app ("sasdata" fileshare).
 */
libname mydata "/shared-data/sasdata";
data mydata.class;
	set sashelp.class;
run;


/* ************************************************************************ */
/* Sample code - launch a CAS session and load data to it                   */
/* ************************************************************************ */

/* Note: this CAS session uses a predefined CASLib persistent backing store 
 * pointing to shared storage. You can transfer data to and from this folder 
 * using the filebrowser web app ("casdata" fileshare).
 */
cas mySession sessopts=(caslib=casuser timeout=1800 locale="en_US");
caslib _all_ assign;

proc casutil;
	load data=mydata.class 
		outcaslib="CASData" casout="sasclass";
quit;

proc casutil;
    save casdata="sasclass" incaslib="CASData" replace
		outcaslib="CASData" casout="sasclass.sashdat";
quit;

cas mySession terminate;
