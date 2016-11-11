*** Settings ***
Documentation     Functional test for bgp - route refresh
...
...               Copyright (c) 2016 Cisco Systems, Inc. and others. All rights reserved.
...
...               This program and the accompanying materials are made available under the
...               terms of the Eclipse Public License v1.0 which accompanies this distribution,
...               and is available at http://www.eclipse.org/legal/epl-v10.html
...
...               This suite tests sending and receiveing route request message.
...               It uses odl and exabgp as bgp peers.
...               Sending route refresh message from odl is initiated via restconf.
...               If route refresh received by odl also correct advertising of routes
...               is verified. Receiving of route refresh by odl is verified by
...               checking appropriate message counter via ${JOLOKURL}. Feature
...               odl-jolokia is required by this test suite.
Suite Setup       Start_Suite
Suite Teardown    Stop_Suite
Test Setup        SetupUtils.Setup_Test_With_Logging_And_Without_Fast_Failing
Library           RequestsLibrary
Library           SSHLibrary
Variables         ${CURDIR}/../../../variables/Variables.py
Resource          ${CURDIR}/../../../libraries/ExaBgpLib.robot
Resource          ${CURDIR}/../../../libraries/Utils.robot
Resource          ${CURDIR}/../../../libraries/SetupUtils.robot
Resource          ${CURDIR}/../../../libraries/TemplatedRequests.robot
Resource          ${CURDIR}/../../../libraries/SSHKeywords.robot
Library           ${CURDIR}/../../../libraries/BgpRpcClient.py    ${TOOLS_SYSTEM_IP}

*** Variables ***
${HOLDTIME}       180
${DEVICE_NAME}    controller-config
${BGP_PEER_NAME}    example-bgp-peer
${RIB_INSTANCE}    example-bgp-rib
${PROTOCOL_OPENCONFIG}    ${RIB_INSTANCE}
${APP_PEER_NAME}    example-bgp-peer-app
${BGP_VAR_FOLDER}    ${CURDIR}/../../../variables/bgpfunctional
${BGP_RR_VAR_FOLDER}    ${BGP_VAR_FOLDER}/route_refresh
${BGP_CFG_NAME}    exa.cfg
${CONFIG_SESSION}    config-session
${EXARPCSCRIPT}    ${CURDIR}/../../../../tools/exabgp_files/exarpc.py
${JOLOKURL}       /jolokia/read/org.opendaylight.controller:instanceName=${BGP_PEER_NAME},type=RuntimeBean,moduleFactoryName=bgp-peer

*** Test Cases ***
Configure_App_Peer
    [Documentation]    Configures bgp application peer. Openconfig is used for carbon and above.
    &{mapping}    BuiltIn.Create_Dictionary    DEVICE_NAME=${DEVICE_NAME}    APP_PEER_NAME=${APP_PEER_NAME}    RIB_INSTANCE_NAME=${RIB_INSTANCE}    APP_PEER_ID=${ODL_SYSTEM_IP}    BGP_RIB_OPENCONFIG=${PROTOCOL_OPENCONFIG}
    ...    IP=${ODL_SYSTEM_IP}
    TemplatedRequests.Put_As_Xml_Templated    ${BGP_VAR_FOLDER}/app_peer    mapping=${mapping}    session=${CONFIG_SESSION}

Reconfigure_ODL_To_Accept_Connection
    [Documentation]    Configures BGP peer module with initiate-connection set to false.
    &{mapping}    BuiltIn.Create_Dictionary    DEVICE_NAME=${DEVICE_NAME}    BGP_NAME=${BGP_PEER_NAME}    IP=${TOOLS_SYSTEM_IP}    HOLDTIME=${HOLDTIME}    PEER_PORT=${BGP_TOOL_PORT}
    ...    INITIATE=false    RIB_INSTANCE_NAME=${RIB_INSTANCE}    BGP_RIB_OPENCONFIG=${PROTOCOL_OPENCONFIG}    PASSIVE_MODE=true
    TemplatedRequests.Put_As_Xml_Templated    ${BGP_VAR_FOLDER}/bgp_peer    mapping=${mapping}    session=${CONFIG_SESSION}

Exa_To_Send_Route_Request
    [Documentation]    Exabgp sends route refresh and count received updates
    [Setup]    Configure_Routes_And_Start_ExaBgp    ${BGP_CFG_NAME}
    # TODO: remove Run_Keyword_If_At_Most_Boron and leave Verify_Odl_Received_Route_Request only after bug 5032 is implemented.
    # ... This will require also kw Verify_Odl_Received_Route_Request adaptation for ${ODL_STREAM} as the stats url will be different in carbon/openconfig
    # ... comparing to boron(${JOLOKURL})
    CompareStream.Run_Keyword_If_At_Most_Boron    Verify_Odl_Received_Route_Request    0
    BgpRpcClient.exa_clean_received_update_count
    BgpRpcClient.exa_announce    announce route-refresh ipv4 unicast
    CompareStream.Run_Keyword_If_At_Most_Boron    BuiltIn.Wait_Until_Keyword_Succeeds    5x    2s    Verify_Odl_Received_Route_Request    1
    BuiltIn.Wait_Until_Keyword_Succeeds    5x    2s    Verify_ExaBgp_Received_Updates    ${nr_configured_routes}
    [Teardown]    Deconfigure_Routes_And_Stop_ExaBgp

Odl_To_Send_Route_Request
    [Documentation]    Sends route requests and checks if exabgp receives it
    [Setup]    ExaBgpLib.Start_ExaBgp_And_Verify_Connected    ${BGP_CFG_NAME}    ${CONFIG_SESSION}    ${TOOLS_SYSTEM_IP}
    BgpRpcClient.exa_clean_received_route_refresh_count
    &{mapping}    BuiltIn.Create_Dictionary    BGP_PEER_IP=${TOOLS_SYSTEM_IP}
    TemplatedRequests.Post_As_Xml_Templated    ${BGP_VAR_FOLDER}/route_refresh    mapping=${mapping}    session=${CONFIG_SESSION}
    BuiltIn.Wait_Until_Keyword_Succeeds    5x    2s    Verify_Odl_Sent_Route_Request    1
    [Teardown]    ExaBgpLib.Stop_ExaBgp

Delete_Bgp_Peer_Configuration
    [Documentation]    Revert the BGP configuration to the original state: without any configured peers.
    &{mapping}    BuiltIn.Create_Dictionary    DEVICE_NAME=${DEVICE_NAME}    BGP_NAME=${BGP_PEER_NAME}    IP=${TOOLS_SYSTEM_IP}    BGP_RIB_OPENCONFIG=${PROTOCOL_OPENCONFIG}
    TemplatedRequests.Delete_Templated    ${BGP_VAR_FOLDER}/bgp_peer    mapping=${mapping}    session=${CONFIG_SESSION}

Deconfigure_App_Peer
    [Documentation]    Revert the BGP configuration to the original state: without application peer
    &{mapping}    BuiltIn.Create_Dictionary    DEVICE_NAME=${DEVICE_NAME}    APP_PEER_NAME=${APP_PEER_NAME}    IP=${ODL_SYSTEM_IP}    BGP_RIB_OPENCONFIG=${PROTOCOL_OPENCONFIG}
    TemplatedRequests.Delete_Templated    ${BGP_VAR_FOLDER}/app_peer    mapping=${mapping}    session=${CONFIG_SESSION}

*** Keywords ***
Start_Suite
    [Documentation]    Suite setup keyword.
    SetupUtils.Setup_Utils_For_Setup_And_Teardown
    ${mininet_conn_id}=    SSHLibrary.Open Connection    ${TOOLS_SYSTEM_IP}    prompt=${DEFAULT_LINUX_PROMPT}    timeout=6s
    Builtin.Set_Suite_Variable    ${mininet_conn_id}
    Utils.Flexible_Mininet_Login    ${TOOLS_SYSTEM_USER}
    SSHKeywords.Virtual_Env_Create
    SSHKeywords.Virtual_Env_Install_Package    exabgp==3.4.16
    RequestsLibrary.Create_Session    ${CONFIG_SESSION}    http://${ODL_SYSTEM_IP}:${RESTCONFPORT}    auth=${AUTH}
    Upload_Config_Files

Stop_Suite
    [Documentation]    Suite teardown keyword
    SSHKeywords.Virtual_Env_Delete
    SSHLibrary.Close_All_Connections
    RequestsLibrary.Delete_All_Sessions

Upload_Config_Files
    [Documentation]    Uploads exabgp config files
    SSHLibrary.Put_File    ${BGP_VAR_FOLDER}/${BGP_CFG_NAME}    .
    SSHLibrary.Put_File    ${EXARPCSCRIPT}    .
    @{cfgfiles}=    SSHLibrary.List_Files_In_Directory    .    *.cfg
    : FOR    ${cfgfile}    IN    @{cfgfiles}
    \    SSHLibrary.Execute_Command    sed -i -e 's/EXABGPIP/${TOOLS_SYSTEM_IP}/g' ${cfgfile}
    \    SSHLibrary.Execute_Command    sed -i -e 's/ODLIP/${ODL_SYSTEM_IP}/g' ${cfgfile}
    \    SSHLibrary.Execute_Command    sed -i -e 's/ROUTEREFRESH/enable/g' ${cfgfile}
    \    SSHLibrary.Execute_Command    sed -i -e 's/ADDPATH/disable/g' ${cfgfile}
    \    ${stdout}=    SSHLibrary.Execute_Command    cat ${cfgfile}
    \    Log    ${stdout}

Configure_Routes_And_Start_ExaBgp
    [Arguments]    ${cfg_file}
    [Documentation]    Setup keyword for exa to odl test case
    ${app_rib}    CompareStream.Set_Variable_If_At_Most_Boron    example-app-rib    ${ODL_SYSTEM_IP}
    : FOR    ${prefix}    IN    1.1.1.1/32    2.2.2.2/32
    \    &{mapping}    BuiltIn.Create_Dictionary    PREFIX=${prefix}    APP_RIB=${app_rib}
    \    TemplatedRequests.Post_As_Xml_Templated    ${BGP_RR_VAR_FOLDER}/route    mapping=${mapping}    session=${CONFIG_SESSION}
    BuiltIn.Set_Suite_Variable    ${nr_configured_routes}    2
    ExaBgpLib.Start_ExaBgp_And_Verify_Connected    ${cfg_file}    ${CONFIG_SESSION}    ${TOOLS_SYSTEM_IP}
    BuiltIn.Wait_Until_Keyword_Succeeds    3x    3s    Verify_ExaBgp_Received_Updates    ${nr_configured_routes}

Deconfigure_Routes_And_Stop_ExaBgp
    [Documentation]    Teardown keyword for exa to odl test case
    ExaBgpLib.Stop_ExaBgp
    ${app_rib}    CompareStream.Set_Variable_If_At_Most_Boron    example-app-rib    ${ODL_SYSTEM_IP}
    &{mapping}    BuiltIn.Create_Dictionary    PREFIX=${prefix}    APP_RIB=${app_rib}
    TemplatedRequests.Delete_Templated    ${BGP_RR_VAR_FOLDER}/route    mapping=${mapping}    session=${CONFIG_SESSION}

Verify_Odl_Sent_Route_Request
    [Arguments]    ${expcount}
    [Documentation]    Compares expected count of route request messages on exabgp side
    ${count}=    BgpRpcClient.exa_get_received_route_refresh_count
    BuiltIn.Should Be Equal As Numbers    ${count}    ${expcount}

Verify_Odl_Received_Route_Request
    [Arguments]    ${expcount}
    [Documentation]    Gets numebr of received route requests and compares with given expected count
    ${rsp}=    RequestsLibrary.Get_Request    ${CONFIG_SESSION}    ${JOLOKURL}
    BuiltIn.Log    ${rsp.content}
    BuiltIn.Should_Be_Equal_As_Numbers    ${rsp.status_code}    200
    BuiltIn.Should_Be_Equal_As_Numbers    ${rsp.json()['status']}    200
    BuiltIn.Should_Be_Equal_As_Numbers    ${rsp.json()['value']['BgpSessionState']['messagesStats']['routeRefreshMsgs']['received']['count']['value']}    ${expcount}

Verify_ExaBgp_Received_Updates
    [Arguments]    ${expcount}
    [Documentation]    Gets numebr of received update requests and compares with given expected count
    ${count_recv}=    BgpRpcClient.exa_get_received_update_count
    BuiltIn.Should Be Equal As Numbers    ${count_recv}    ${expcount}
