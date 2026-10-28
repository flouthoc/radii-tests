#!/bin/bash
. /usr/share/beakerlib/beakerlib.sh

: ${RADII=radii}

rlJournalStart
    rlPhaseStartSetup
        rlAssertRpm radii || exit 1
        rlRun "command -v ${RADII}" || exit 1

        eval $(grep -E '^(ID|VERSION_ID)=' /etc/os-release)
        if test ${ID} != rhel; then
            rlFail "Test requires a RHEL system (found ID=${ID})"
            exit 1
        fi
        rhel_version=${VERSION_ID%%.*}
        arch=$(uname -m)

        repofile=/etc/yum.repos.d/radii-nvidia-partner.repo
        rlFileBackup --clean /etc/yum.repos.d/redhat.repo
        rlFileBackup --clean ${repofile}
        rlFileBackup --clean /usr/sbin/subscription-manager
        rlFileBackup --clean /etc/radii/config.yaml

        printf '#!/bin/bash\nexit 0\n' >/usr/sbin/subscription-manager
        chmod 755 /usr/sbin/subscription-manager

        sslkey=/etc/pki/entitlement/test-key.pem
        sslcert=/etc/pki/entitlement/test.pem
        for channel in baseos appstream extensions supplementary; do
            cat <<REPO
[rhel-${rhel_version}-for-${arch}-${channel}-rpms]
name = ${channel}
enabled = 1
sslclientkey = ${sslkey}
sslclientcert = ${sslcert}

REPO
        done >/etc/yum.repos.d/redhat.repo
    rlPhaseEnd

    rlPhaseStartTest "Partner repo is created with --partner-repo"
        # install with --partner-repo calls EnsurePartnerReposEnabled
        # which writes radii-nvidia-partner.repo.  The install will fail
        # because the repos are stubs, so ignore the exit code and verify
        # only the generated file.
        ${RADII} --debug --partner-repo install --force --batch nvidia 2>stderr || true

        rlAssertExists ${repofile}
        rlAssertGrep '^\[radii-partner-nvidia-cuda\]$' ${repofile}
        rlAssertGrep "custom-1-${arch}" ${repofile} -F
        rlAssertGrep "cuda-monorepo-rhel-${rhel_version}" ${repofile} -F
        rlAssertGrep '^enabled=1$' ${repofile}
        rlAssertGrep "^sslclientkey=${sslkey}$" ${repofile}
        rlAssertGrep "^sslclientcert=${sslcert}$" ${repofile}
        rlAssertGrep '^gpgcheck=1$' ${repofile}
        rlAssertGrep '^sslverify=1$' ${repofile}
    rlPhaseEnd

    rlPhaseStartTest "List does not write partner repo file"
        # list is read-only so partner repo details are passed as inline
        # DNF arguments; no repo file should be written.
        rm -f ${repofile}
        ${RADII} --debug --partner-repo list 2>stderr || true
        rlAssertNotExists ${repofile}
    rlPhaseEnd

    rlPhaseStartTest "Partner repo is not created without --partner-repo"
        rm -f ${repofile}
        ${RADII} --debug install --force --batch nvidia 2>stderr || true
        rlAssertNotExists ${repofile}
    rlPhaseEnd

    rlPhaseStartTest "Partner repo is not created with --skip-subscriptions"
        rm -f ${repofile}
        ${RADII} --debug --partner-repo --skip-subscriptions install --force --batch nvidia 2>stderr || true
        rlAssertNotExists ${repofile}
    rlPhaseEnd

    rlPhaseStartTest "Config persists partner-repos setting"
        rm -f /etc/radii/config.yaml
        rlRun "${RADII} config partner-repos true"
        rlAssertExists /etc/radii/config.yaml
        rlAssertGrep 'partner-repos: true' /etc/radii/config.yaml -F
        rlRun "${RADII} config partner-repos false"
        rlAssertGrep 'partner-repos: false' /etc/radii/config.yaml -F
    rlPhaseEnd

    rlPhaseStartTest "Config partner-repos enables partner repo during install"
        rm -f ${repofile}
        rlRun "${RADII} config partner-repos true"
        ${RADII} --debug install --force --batch nvidia 2>stderr || true
        rlAssertExists ${repofile}
        rm -f /etc/radii/config.yaml
    rlPhaseEnd

    rlPhaseStartCleanup
        rlFileRestore
    rlPhaseEnd
rlJournalEnd
rlJournalPrintText
