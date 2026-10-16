#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>
#include <systemd/sd-daemon.h>

static volatile sig_atomic_t hang_requested = 0;

static void handle_sigusr1(int signo)
{
    (void)signo;
    hang_requested = 1;
}

int main(void)
{
    struct sigaction action = {0};
    action.sa_handler = handle_sigusr1;
    sigemptyset(&action.sa_mask);
    if (sigaction(SIGUSR1, &action, NULL) == -1) {
        perror("sigaction");
        return EXIT_FAILURE;
    }

    uint64_t watchdog_usec = 0;
    int enabled = sd_watchdog_enabled(0, &watchdog_usec);
    if (enabled <= 0) {
        fprintf(stderr, "Watchdog is not enabled (result=%d)\n", enabled);
        return EXIT_FAILURE;
    }

    printf("KCSM demo started: PID=%ld, deadline=%.1fs\n",
           (long)getpid(), watchdog_usec / 1000000.0);
    fflush(stdout);

    if (sd_notify(0, "READY=1") <= 0) {
        fprintf(stderr, "Failed to send READY=1\n");
        return EXIT_FAILURE;
    }

    unsigned long round = 0;
    for (;;) {
        if (hang_requested) {
            printf("SIMULATED HANG: PID=%ld is alive, but no more WATCHDOG=1\n",
                   (long)getpid());
            fflush(stdout);
            for (;;) pause();  /* 故意不再发送心跳 */
        }

        /* 模拟 KCSM 完成一次监控周期 */
        printf("round=%lu: corosync/pacemaker/qdevice checked\n", ++round);
        if (sd_notify(0, "WATCHDOG=1") <= 0) {
            fprintf(stderr, "Failed to send WATCHDOG=1\n");
            return EXIT_FAILURE;
        }
        printf("WATCHDOG=1 sent\n");
        fflush(stdout);

        /* 收到 SIGUSR1 会打断 sleep，下一轮进入 Hang */
        sleep(1);
    }
}
