# Common UBSan Failure Patterns

Quick reference for interpreting UBSan reports and applying the right fix.

## Signed integer overflow

```
runtime error: signed integer overflow: 2147483647 + 1 cannot be represented in type 'int'
```

**Cause**: signed overflow is UB in C++.
**Fix**:
- Use larger type (`int64_t`) if the value can grow
- Use unsigned if overflow wrap is intentional (it's defined for unsigned)
- Add bounds check before the arithmetic

## Misaligned pointer use

```
runtime error: load of misaligned address 0x... for type 'int', which requires 4 byte alignment
```

**Cause**: reading a pointer that's not aligned to the type's required alignment.
**Fix**:
- `memcpy` to a properly aligned local
- Use `alignas` for storage
- Don't punt aligned-ness through char* casts

## Null pointer dereference

```
runtime error: load of null pointer of type '...'
```

**Cause**: dereferencing nullptr.
**Fix**: null-check before deref. If the API contract says non-null, fix the caller.

## Division by zero

```
runtime error: division by zero
```

**Fix**: guard the divisor. For floating point, check `std::isnormal(divisor)` if you care about subnormals.

## Shift overflow

```
runtime error: shift exponent 33 is too large for 32-bit type 'int'
```

**Fix**: mask the shift amount: `x << (n & 31)`. Or use a larger type.

## Reference bound to null pointer

```
runtime error: reference binding to null pointer of type '...'
```

**Cause**: `&*p` where `p` is null.
**Fix**: check `p` before deref.

## std::vector out-of-bounds

```
runtime error: index 10 out of bounds for type 'int [10]'
```

**Fix**: use `.at()` instead of `[]` if you can't prove safety. Or fix the index logic.

## Float-cast-overflow

```
runtime error: 1.5e+10 is outside the range of representable values of type 'int'
```

**Fix**: bounds-check before casting `double` → `int`. Or use saturating cast.

## When UBSan stops you in third-party code

Often you'll see UB in a vendored library you don't own. Options:
1. Suppress with `UBSAN_OPTIONS=suppressions=...` if it's known harmless
2. File issue upstream with the report
3. If critical: fork + patch
4. Don't disable UBSan globally to make it go away
