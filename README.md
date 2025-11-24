# MirrorWatch

[![CI](https://github.com/aaronwittchen/MirrorSync/actions/workflows/ci.yml/badge.svg)](https://github.com/aaronwittchen/MirrorSync/actions/workflows/ci.yml)
[![Tests](https://github.com/aaronwittchen/MirrorSync/actions/workflows/tests.yml/badge.svg)](https://github.com/aaronwittchen/MirrorSync/actions/workflows/tests.yml)
[![Ruby Version](https://img.shields.io/badge/ruby-3.2%2B-red.svg)](https://www.ruby-lang.org/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A production-grade mirror synchronization system for Linux distribution repositories. Built in Ruby with rsync integration, MirrorWatch handles automated mirroring of Debian, Ubuntu, Arch Linux, and other distribution repositories with enterprise reliability features.

> **Note:** This is a very early work in progress

## Overview

MirrorWatch is a mirror synchronization tool designed for operating mirror infrastructure. It wraps rsync with additional operational features including bandwidth management, concurrent operation prevention, selective synchronization, and structured logging. The system is built to handle both small-scale personal mirrors and production mirror services.

**Primary Use Cases:**
- Public mirror services for Linux distributions
- Internal package repository mirrors for enterprises
- Development and testing of mirror infrastructure
- Learning mirror operations and automation

**Technical Foundation:**
- Ruby 3.2+ with rsync backend
- File-based locking using POSIX flock
- Structured JSON logging for log aggregation
- Comprehensive test coverage (40+ test cases)

## Key Features

### Synchronization
- Multi-mirror configuration support
- Rsync-based file transfer with compression
- Hard-link preservation for storage efficiency
- Bandwidth throttling (configurable per mirror)
- Include/exclude pattern filtering
- Dry-run mode for testing

### Operations
- File-based locking to prevent concurrent syncs
- Structured JSON logging with detailed metrics
- Error handling with exit status tracking
- Statistics tracking (files transferred, bandwidth used, duration)
- Configurable via YAML files

### Quality Assurance
- Full test suite with RSpec
- RuboCop linting integration
- Automated CI/CD pipeline support
- Production-tested codebase

## Usage

Run the sync command:

```bash
bin/mirrorwatch sync
```
