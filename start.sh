#!/bin/bash
docker build -t nimd:latest . 
docker run --rm -it nimd