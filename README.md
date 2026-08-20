# Multi-Protocol RTL Verification

## Overview

Designed and verified synthesizable **UART, SPI, and I2C communication controllers** using SystemVerilog. The project includes protocol-specific RTL, simulation testbenches, functional coverage, assertion-based verification, protocol switching, and fault-injection scenarios.

## Features

* UART transmitter with configurable baud-rate divider
* SPI Master supporting Mode 0 communication
* I2C Master with START, address, ACK, data, and STOP sequencing
* Protocol selection and switching logic
* SystemVerilog functional coverage
* Assertion-based protocol verification
* Fault injection and fault detection
* Unified verification environment for multiple protocols

## Repository Structure

```text
rtl/              - Synthesizable RTL modules
testbench/        - Protocol-specific and unified testbenches
verification/     - Functional coverage
fault_injection/  - Fault models and fault-detection testbenches
docs/             - Waveforms, block diagrams, and verification results
```

## Technologies

* SystemVerilog
* RTL Design
* SystemVerilog Assertions
* Functional Coverage
* Xilinx Vivado / XSim

## Verification

The design was verified using dedicated testbenches for UART, SPI, and I2C along with a unified test environment. Verification includes normal operating scenarios, protocol checks, corner cases, functional coverage, and injected-fault scenarios.

## Fault Injection

Fault models were developed to evaluate the ability of assertions and verification logic to detect protocol and control failures, including UART output corruption, SPI chip-select faults, I2C SDA glitches, and protocol-enable conflicts.

## Results

* Functional behavior verified through simulation
* Protocol-specific test scenarios executed for UART, SPI, and I2C
* Assertion-based fault detection implemented
* Functional coverage collected using SystemVerilog covergroups
* Fault-injection scenarios successfully exercised during simulation
