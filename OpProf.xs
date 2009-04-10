#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#define NEED_newRV_noinc
#include "ppport.h"

#include <time.h>
#include <sys/resource.h>

static int (*runops_original)(pTHX);
static int is_runnning = 0;
static int skip_count  = 0; /* it skips first 4 times */

#define USEC 1000000

HV *capture;

/*
 * capture of running opes status
 */
void
opcode_capture(OP *op, IV sec) {
    HV *op_stash;
    char seq[64];
    I32 seq_len;

    if (skip_count) {
        skip_count--;
        return;
    }

    seq_len = sprintf(seq, "%d", op->op_seq);

    /* fetch the op stash */
    if (hv_exists(capture, seq, seq_len)) {
        SV **rv;
        rv = hv_fetch(capture, seq, seq_len, 0);
        if (!rv) {
            is_runnning = 0;
            croak("broken the capture hash");
        }
        op_stash = (HV *) SvRV(*rv);
    } else {
        /* create new entry */
        op_stash = newHV();
        hv_store(op_stash, "type",  4, newSViv(op->op_type), 0); 
        hv_store(op_stash, "steps", 5, newSViv(0), 0);
        hv_store(op_stash, "usec",  4, newSViv(0), 0);

        hv_store(capture, seq, seq_len, newRV_noinc((SV *) op_stash), 0);
    }

    /* increment of status */
    if (op_stash) {
        SV **count;
        SV **usec;
        count = hv_fetch(op_stash, "steps", 5, 0);
        usec  = hv_fetch(op_stash, "usec", 4, 0);
        if (!count || !usec) {
            is_runnning = 0;
            croak("broken the capture hash seq: %s", seq);
        }
        SvIV_set(*count, SvIV(*count) + 1);
        SvIV_set(*usec, SvIV(*usec) + sec);
    }
}

/*
 * PL_runopes for Devel::OpProf
 */
int
opprof_runops(pTHX)
{   
    struct timeval tv;
    int status;
    IV sec;
    struct rusage rusage1, rusage2;

    while (1) {

        if (is_runnning) {
            /* profile mode */

            /* getting first time */
            getrusage(RUSAGE_SELF, &rusage1);

            /* we need boolean value */
            status = !!!(PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX));

            /* making running time of op */
            getrusage(RUSAGE_SELF, &rusage2);
            sec = ((rusage2.ru_utime.tv_sec * USEC) + rusage2.ru_utime.tv_usec) - ((rusage1.ru_utime.tv_sec * USEC) + rusage1.ru_utime.tv_usec);

            if (status) {
                break;
            }
            opcode_capture(PL_op, sec);
        } else {
            if (!(PL_op = CALL_FPTR(PL_op->op_ppaddr)(aTHX))) {
                break;
            }
        }
        PERL_ASYNC_CHECK();
    }

    TAINT_NOT;
    return 0;
}

MODULE = Devel::OpProf          PACKAGE = Devel::OpProf

PROTOTYPES: DISABLE

void
start(capture_hash)
    HV *capture_hash
    CODE:
        hv_clear(capture_hash);
        capture     = capture_hash;
        is_runnning = 1;
        skip_count  = 4;

void
stop()
    CODE:
        is_runnning = 0;

BOOT:
    runops_original = PL_runops;
    PL_runops = opprof_runops;
