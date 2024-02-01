*** Settings ***
Documentation     Kueue E2E tests - https://github.com/opendatahub-io/kueue.git
Suite Setup       Prepare Kueue E2E Test Suite
Suite Teardown    Teardown Kueue E2E Test Suite
Library           OperatingSystem
Library           Process
Library           OpenShiftLibrary


*** Variables ***
${KUEUE_DIR}            kueue
${KUEUE_REPO_URL}       %{KUEUE_REPO_URL=https://github.com/opendatahub-io/kueue.git}
${KUEUE_REPO_BRANCH}    %{KUEUE_REPO_BRANCH=main}
${JOB_GO_BIN}           %{WORKSPACE=.}/go-bin
${KUBECONFIG}           %{WORKSPACE=.}/kconfig
${WORKER_NODE}          ${EMPTY}


*** Test Cases ***
Run E2E test
    [Documentation]    Run ginkgo E2E single cluster test
    [Tags]  Kueue
    ...     DistributedWorkloads
    Run Kueue E2E Test    e2e_test.go

Run Visibility test
    [Documentation]    Run ginkgo visibilty single cluster test
    [Tags]  Kueue
    ...     DistributedWorkloads
    Enable Visibility Feature Gate
    Run Kueue E2E Test    visibility_test.go


*** Keywords ***
Prepare Kueue E2E Test Suite
    [Documentation]    Prepare Kueue E2E Test Suite
    ${result} =    Run Process    git clone -b ${KUEUE_REPO_BRANCH} ${KUEUE_REPO_URL} ${KUEUE_DIR}
    ...    shell=true    stderr=STDOUT
    Log To Console    ${result.stdout}
    IF    ${result.rc} != 0
        FAIL    Unable to clone kueue repo ${KUEUE_REPO_URL}:${KUEUE_REPO_BRANCH}:${KUEUE_DIR}
    END

    Log To Console    Install the latest development version of kueue ...
    ${return_code}    ${output}    Run And Return Rc And Output    kubectl apply --server-side -k "github.com/kubernetes-sigs/kueue/config/default?ref=main"
    Log To Console    ${output}
    Should Be Equal As Integers   ${return_code}   0  msg=Error detected while installing kueue

    # Add label instance-type=on-demand on worker node
    Log To Console    Add label on worker node ...
    ${return_code}    ${output}    Run And Return Rc And Output    oc get nodes -o name --selector=node-role.kubernetes.io/worker | tail -n1
    Set Suite Variable    ${WORKER_NODE}    ${output}
    ${return_code} =    Run And Return Rc    oc label ${WORKER_NODE} instance-type=on-demand
    Should Be Equal As Integers  ${return_code}   0   msg=Fail to label worker node with instance-type=on-demand

    # Use Go install command to install ginkgo
    Log To Console    Install ginkgo ...
    ${result} =    Run Process    go install github.com/onsi/ginkgo/v2/ginkgo
    ...    shell=true    stderr=STDOUT
    ...    env:GOBIN=${JOB_GO_BIN}
    ...    cwd=${KUEUE_DIR}
    Log To Console    ${result.stdout}
    IF    ${result.rc} != 0
        FAIL    Fail to install ginkgo
    END


Teardown Kueue E2E Test Suite
    [Documentation]    Teardown Kueue E2E Test Suite
    Log To Console    Uninstall Kueue ...
    ${return_code}    ${output}    Run And Return Rc And Output    kubectl delete -k "github.com/kubernetes-sigs/kueue/config/default?ref=main" --ignore-not-found=true
    Log To Console    ${output}
    Should Be Equal As Integers   ${return_code}   0  msg=Error detected while uninstalling kueue

    # Remove label instance-type=on-demand from worker node
    Log To Console    Remove label from worker node ...
    ${return_code} =    Run And Return Rc    oc label ${WORKER_NODE} instance-type-
    Should Be Equal As Integers  ${return_code}   0   msg=Fail to unlabel instance-type=on-demand from worker node

Run Kueue E2E Test
    [Documentation]    Run Kueue E2E Test
    [Arguments]    ${test_name}
    Log To Console    Running Kueue E2E test: ${test_name}
    ${result} =    Run Process    ginkgo --focus-file\=${test_name} ${KUEUE_DIR}/test/e2e/singlecluster
    ...    shell=true    stderr=STDOUT
    ...    env:PATH=%{PATH}:${JOB_GO_BIN}
    ...    env:KUBECONFIG=${KUBECONFIG}
    Log To Console    ${result.stdout}
    IF    ${result.rc} != 0
        FAIL    failed
    END

Enable Visibility Feature Gate
    [Documentation]    Enable Visibility Feature Gate
    ${return_code} =    Run And Return Rc    oc patch deployment kueue-controller-manager -n kueue-system --type 'json' -p '[{"op" : "add" ,"path" : "/spec/template/spec/containers/0/args/-" ,"value" : "--feature-gates=VisibilityOnDemand=true"}]'
    Should Be Equal As Integers  ${return_code}   0   msg=Visiblity feature gate is not enabled

    ${return_code} =    Run And Return Rc    oc rollout status deployment/kueue-controller-manager -n kueue-system --timeout=3m
    Should Be Equal As Integers  ${return_code}   0   msg=Kueue rollout failed