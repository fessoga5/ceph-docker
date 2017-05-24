#!/bin/bash -x

. $WORKSPACE/.tox_vars
cd $CEPH_ANSIBLE_SCENARIO_PATH
vagrant destroy --force
cd $WORKSPACE
