# AI Extension Makefile for PostgreSQL

MODULE_big = ai
OBJS = ai.o

EXTENSION = ai
DATA = ai--1.0.sql

# ONNX Runtime configuration
ONNXRUNTIME_DIR = /opt/onnxruntime
SHLIB_LINK += -L$(ONNXRUNTIME_DIR)/lib -lonnxruntime
PG_CPPFLAGS += -I$(ONNXRUNTIME_DIR)/include

# Use PGXS for building
PG_CONFIG = pg_config
PGXS := $(shell $(PG_CONFIG) --pgxs)
include $(PGXS)
