# Container slot multiplication must fail before it can wrap to a small
# backing allocation and turn initialization into an out-of-bounds write.
call __lsl_int_zeros(1152921504606846976)
