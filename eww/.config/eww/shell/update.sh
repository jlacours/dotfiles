#!/bin/env bash

repo=$(checkupdates 2>/dev/null | wc -l)
echo "$repo"
