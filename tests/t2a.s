	.file	"t2a.c"
	.option nopic
	.attribute arch, "rv32i2p0"
	.attribute unaligned_access, 0
	.attribute stack_align, 16
	.text
	.align	2
	.globl	main
	.type	main, @function
main:
	addi	sp,sp,-32
	sw	s0,28(sp)
	addi	s0,sp,32
	sw	zero,-20(s0)
	li	a5,4096
	sw	a5,-24(s0)
.L2:
	lw	a4,-20(s0)
	lw	a5,-24(s0)
	sw	a4,0(a5)
	lw	a5,-20(s0)
	addi	a5,a5,4
	sw	a5,-20(s0)
	j	.L2
	.size	main, .-main
	.align	2
	.globl	add
	.type	add, @function
add:
	addi	sp,sp,-32
	sw	s0,28(sp)
	addi	s0,sp,32
	sw	a0,-20(s0)
	sw	a1,-24(s0)
	lw	a4,-20(s0)
	lw	a5,-24(s0)
	add	a5,a4,a5
	mv	a0,a5
	lw	s0,28(sp)
	addi	sp,sp,32
	jr	ra
	.size	add, .-add
	.ident	"GCC: (GNU) 9.2.0"
