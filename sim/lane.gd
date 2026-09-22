class_name Lane
extends RefCounted
## A starlane between two systems (indices into Galaxy.systems). Lanes are
## two-way; `length` is the straight-line distance in light years.

var a: int
var b: int
var length: float

func _init(a_: int, b_: int, length_: float) -> void:
	a = a_
	b = b_
	length = length_

## The system at the other end of the lane from `i`.
func other(i: int) -> int:
	return b if i == a else a
