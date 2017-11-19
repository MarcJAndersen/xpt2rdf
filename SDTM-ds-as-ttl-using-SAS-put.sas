/*
Purpose: transfer SAS export files (.xpt) to RDF turtle using very simple approach
Note: Designed for demonstration, not for production
*/


data xptfiles;
    drop rc did msg memcount i;
    rc= filename("xptdir","../phuse-scripts/data/sdtm/updated_cdiscpilot");
    dirname=  pathname("xptdir");
    did= dopen("xptdir");
    if did=0 then do;
        msg=sysmsg();
        put msg;
        abort cancel;
        end;
    else do;
        memcount=dnum(did);
        do i=1 to memcount;
            fname=dread(did, i);
            if lowcase(scan(fname,-1,"."))="xpt" then do;
                put i= fname=;
                output;
                end;
            end;
        end;
run;

%MACRO DoImport(indsn, xptdsn);
data &indsn.;
    set &xptdsn.(obs=10);
    run;
    proc contents data=&indsn. varnum;
    run;
    proc print data=&indsn.(obs=2) width=min;
    run;    
%MEND;

data datasets;
    set xptfiles(obs=2);

   length ttlfilename xptfilepath $200;
   xptfilepath=catx("\",dirname,fname);
   length member indsn $65;
   member= scan(fname,-2,".");

   rc=libname("xptfile",xptfilepath, "xport");
   putlog rc= xptfilepath=;
   xptdsn= catx(".", "xptfile", member);
   indsn= catx(".", "work", member);
   rc=dosubl(cats('%DoImport(', catx(", ", indsn, xptdsn), ')' ));

   ttlfilename= cats(translate(member,".","-"),".ttl");
   xptfileseqno+1;
   
   putlog member= ttlfilename=;
run;

    
proc print data=xptfiles width=min;
run;

%let maxl=$2048;
%let outlinelen=$3072;

data _null_;
    set datasets;
    by xptfileseqno;

    t_ttlfilename=ttlfilename;
    file dummy filevar=t_ttlfilename lrecl=&outlinelen.; 

    length line &outlinelen.; /* maximal length of text line */
    length stext ptext otext &outlinelen.; 
    length xsvaluec &maxl.; /* maximal length of any character variable */
    length xsdsn $32 xsvar $32;
    length xsfmt $33;
    length indsn $65;

    if first.xptfileseqno then do;
        put "@prefix ds: <http://example.org/sasdataset#> .";
        put "@prefix dsv: <http://example.org/sasdataset-variable#> .";
        put "@prefix rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#> .";
        put "@prefix xsd: <http://www.w3.org/2001/XMLSchema#> .";
        put " ";
    end;

    putlog " opening ... " indsn= ;
    dsid=open(indsn,"i");
    if dsid=0 then do;
        put "Could not open " indsn=;
        abort cancel;
        end;
    xsdsn=indsn;
    numvars=attrn(dsid,"nvars");
    nobs=attrn(dsid,"nobs");


    do j=1 to min(nobs,10);
        rc= fetchobs(dsid, j);
        stext= cats("_:", j, "_", indsn );
        ptext= "rdf:type";
        otext= cats("ds:", indsn );
        indentpos=1;
        put;
        do i=1 to numvars;
            line= catx(" ", stext, ptext, otext, ";" );
            put @indentpos line : +(-1); /* remove trailing blank */
            indentpos=4;
            xsvar=varname(dsid,i);
            xsfmt=varfmt(dsid,i);
            stext=" "; 
            ptext=cats("dsv:", cats(member,".", xsvar));
            /* Determine type from format, to make it easier to later add all datetime, date and time formats */
            /* The code below is inefficient. Using a lookup table could be faster, and mapping could be determined initially */
            select;
            when (vartype(dsid,i)="N" and xsfmt="E8601DT.") do;
                xsvaluen= getvarn( dsid, i);            
                otext= cats(quote(strip(put(xsvaluen,E8601DT.))),"^^xsd:dateTime");
                end;
            when (vartype(dsid,i)="N" and xsfmt="E8601DA.") do;
                xsvaluen= getvarn( dsid, i);
                otext= cats(quote(strip(put(xsvaluen,E8601DA.))),"^^xsd:date");
                end;
            when (vartype(dsid,i)="N" and xsfmt="E8601TM.") do;
                xsvaluen= getvarn( dsid, i);
                otext= cats(quote(strip(put(xsvaluen,E8601TM.))),"^^xsd:time");
                end;
            when (vartype(dsid,i)="N" and xsfmt=:"E") do;
                xsvaluen= getvarn( dsid, i);
                otext= cats(quote(strip(vvalue(xsvaluen))),"^^xsd:float");
                end;
            when (vartype(dsid,i)="N") do;
                /* Assuming everything else is float and representing as float */
                xsvaluen= getvarn( dsid, i);
                if missing(xsvaluen) then do;
                        otext= cats("NaN","^^xsd:float");
                    end;
                    else do;
                        otext= cats(strip(put(xsvaluen,e32.)),"^^xsd:float");
                        end;
                end;
            when (vartype(dsid,i)="C") do;
                xsvaluec= getvarc( dsid, i);
                /* Using trim to avoid trailing blanks. Deliberately not stripping leading blanks */
                otext= quote(trim(xsvaluec));
                end;
                end; /* select */
           end;
            line= catx(" ", stext, ptext, otext, "." );
            put @indentpos line : +(-1); /* remove trailing blank */
        end;
    /* === All done for dataset === */
    rc=close(dsid);

run;

        
