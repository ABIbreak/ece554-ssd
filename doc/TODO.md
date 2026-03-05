## Control & Status Registers (CSRs)
- [ ] Find verification IP
- [ ] Upload reference materials for PCIe
- [ ] ^ for NVMe
- [ ] NVMe queues
	- [ ] Verify SoC registers set base address for host registers
- [ ] Doorbell Registers
	- [ ] Verify writes to completion doorbell registers trigger interrupts
- [ ] Modules
	- [ ] Basics
		- [ ] Single-sided R/W
		- [ ] Double-sided R/W
		- [ ] Read side & write side
	- [ ] PCIe Configuration Header
	- [ ] PCIe MSI Capabilities
	- [ ] NVMe Controller Properties
	- [ ] NVMe Submission/Completion Queues
	- [ ] NVMe Doorbell Registers

## Flash Controller
- [ ] Figure out how the OpenSSD firmware interfaces with the flash controller, i.e. flash addr and bounds, flash directly memory-mapped, etc.
- [ ] Scrambler
	- [ ] Find reference implementation
- [ ] Find ONFI model from Micron
- [x] Check if FMC and tristate buffers are compatible
	- They are! "Yes, you can use the FMC LA, HA, or HB bank pins as single-ended signals with tristate buffers using IOBUF primitives in HDL." - IAM Electronic
- [ ] 

## PCB
- [ ] Implement channels
- [ ] Add level shifter
- [ ] Check FMC header for shorts
- [ ] PCBA
	- [ ] Configure PCB to be PCBA-ready
	- [ ] Ask for a quote