from sys.info import num_physical_cores
from algorithm import vectorize, parallelize
from memory import memset_zero, memset, stack_allocation, UnsafePointer
from math import sqrt
from random import rand
from utils.numerics import min_finite, max_finite
from utils.index import IndexList

from basalt import Tensor, TensorShape
from basalt.nn.tensor import MAX_RANK
from basalt.utils.math_util import add, sub, mul, div


# ---- Start -----

@always_inline
fn fill[dtype: DType](inout t: Tensor[dtype], val: Scalar[dtype]):
    @parameter
    fn fill_vec[nelts: Int](idx: Int):
        t.store[nelts](idx, val)

    vectorize[fill_vec, nelts](t.num_elements())


# ----- Functions to access positions in tensor data -----
@always_inline
fn get_real_index[
    size: Int, strides_shape: IndexList[size], broadcast_shape: TensorShape
](i: Int) -> Int:
    # broadcast_shape is of same rank as strides_shape (the not broadcasted shape), because of broadcast_calculate_strides
    var index_res = 0
    var linear_index = i

    @parameter
    for dim in range(size):
        alias j = size - 1 - dim
        alias stride_value = strides_shape[j]
        alias shape_value = broadcast_shape[j]

        var divmod_index = divmod(linear_index, shape_value)

        index_res += divmod_index[1] * stride_value
        linear_index = divmod_index[0]

    return index_res


# ----- Broadcast functions -----
@always_inline
fn broadcast_shapes(s1: TensorShape, s2: TensorShape) -> TensorShape:
    var ndim = max(s1.rank(), s2.rank())
    var diff = abs(s1.rank() - s2.rank())

    var big = s1 if s1.rank() > s2.rank() else s2
    var small = s2 if s1.rank() > s2.rank() else s1

    var res = IndexList[MAX_RANK](-1)

    for i in range(ndim - 1, diff - 1, -1):
        var a = big[i]
        var b = small[i - diff]
        if b == a:
            res[i] = a
        elif a == 1 or b == 1:
            res[i] = a * b
        else:
            print("[ERROR] Shapes " + str(s1) + " and " + str(s2) + " cannot be broadcasted together.")

    for i in range(diff - 1, -1, -1):
        res[i] = big[i]

    return TensorShape(rank=ndim, shape=res)


@always_inline
fn broadcast_shapes(*s: TensorShape) -> TensorShape:
    var result_shape = s[0]

    for i in range(1, len(s)):
        result_shape = broadcast_shapes(result_shape, s[i])

    return result_shape


@always_inline
fn broadcast_calculate_strides[size: Int, shape: TensorShape, broadcast_shape: TensorShape]() -> IndexList[size]:
    alias shape_rank = shape.rank()
    alias diff = size - shape_rank

    var strides = IndexList[size](0)

    var stride = 1
    for i in range(shape_rank - 1, -1, -1):
        if shape[i] != 1:
            strides[i + diff] = stride
            stride *= shape[i]

    return strides

# ----- Element-wise unary operations -----
@always_inline
fn elwise_transform[
    func: fn[dtype: DType, nelts: Int] (x: SIMD[dtype, nelts]) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], t: Tensor[dtype]):
    @parameter
    fn vecmath[nelts: Int](idx: Int):
        res.store[nelts](idx, func[dtype, nelts](t.load[nelts](idx)))

    vectorize[vecmath, nelts](t.num_elements())


fn elwise_transform[
    func: fn[dtype: DType, nelts: Int] (x: SIMD[dtype, nelts]) -> SIMD[dtype, nelts],
](inout t: Tensor[dtype]):
    @parameter
    fn vecmath[nelts: Int](idx: Int):
        t.store[nelts](idx, func[dtype, nelts](t.load[nelts](idx)))

    vectorize[vecmath, nelts](t.num_elements())


# ----- Element-wise binary operations -----
@always_inline
fn elwise_pow(inout res: Tensor[dtype], t: Tensor[dtype], x: Int):
    @parameter
    fn vecpow[nelts: Int](idx: Int):
        res.store[nelts](idx, pow(t.load[nelts](idx), x))

    vectorize[vecpow, nelts](t.num_elements())


@always_inline
fn elwise_op[
    t1_shape: TensorShape,
    t2_shape: TensorShape,
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], t1: Tensor[dtype], t2: Tensor[dtype]):
    alias broadcast: Bool = (t1_shape != t2_shape)
    alias is_scalar: Bool = (t2_shape == TensorShape(1))

    @parameter
    if t2_shape == TensorShape(1):
        elwise_op[func](res, t1, t2[0])
    elif t1_shape == TensorShape(1):
        elwise_op[func](res, t1[0], t2)
    elif broadcast and not is_scalar:
        alias res_shape = broadcast_shapes(t1_shape, t2_shape)
        broadcast_elwise_op[t1_shape, t2_shape, res_shape, func](res, t1, t2)
    else:
        elwise_op[func](res, t1, t2)


@always_inline
fn elwise_op[
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], t1: Tensor[dtype], t2: Tensor[dtype]):
    """Element-wise operation on two tensors of equal shape."""

    @parameter
    fn vecmath[nelts: Int](idx: Int):
        res.store[nelts](
            idx, func[dtype, nelts](t1.load[nelts](idx), t2.load[nelts](idx))
        )

    vectorize[vecmath, nelts](t1.num_elements())


@always_inline
fn elwise_op[
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], t1: Tensor[dtype], a: Scalar[dtype]):
    """Element-wise operation on a tensor and a scalar."""

    @parameter
    fn vecmath[nelts: Int](idx: Int):
        res.store[nelts](idx, func[dtype, nelts](t1.load[nelts](idx), a))

    vectorize[vecmath, nelts](t1.num_elements())


@always_inline
fn elwise_op[
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], a: Scalar[dtype], t1: Tensor[dtype]):
    """Element-wise operation on a tensor and a scalar."""

    @parameter
    fn vecmath[nelts: Int](idx: Int):
        res.store[nelts](idx, func[dtype, nelts](a, t1.load[nelts](idx)))

    vectorize[vecmath, nelts](t1.num_elements())


fn broadcast_elwise_op[
    t1_shape: TensorShape,
    t2_shape: TensorShape,
    res_shape: TensorShape,
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], t1: Tensor[dtype], t2: Tensor[dtype]):
    alias size = res_shape.rank()
    alias strides1 = broadcast_calculate_strides[size, t1_shape, res_shape]()
    alias strides2 = broadcast_calculate_strides[size, t2_shape, res_shape]()

    @parameter
    fn vec_op[nelts: Int](i: Int):
        var index1 = get_real_index[size, strides1, res_shape](i)
        var index2 = get_real_index[size, strides2, res_shape](i)

        res.store[nelts](
            i,
            func[dtype, nelts](t1.load[nelts](index1), t2.load[nelts](index2)),
        )

    # TODO: Check how to vectorize this
    vectorize[vec_op, 1](res.num_elements())


@always_inline
fn accumulate_op[
    res_shape: TensorShape,
    t1_shape: TensorShape,
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], t1: Tensor[dtype]):
    if res_shape == t1_shape:
        accumulate_op[func](res, t1)

    alias size = res_shape.rank()
    alias strides1 = broadcast_calculate_strides[size, t1_shape, res_shape]()

    @parameter
    fn vec_op[nelts: Int](i: Int):
        var index1 = get_real_index[size, strides1, res_shape](i)

        res.store[nelts](i, func[dtype, nelts](res.load[nelts](i), t1.load[nelts](index1)))

    vectorize[vec_op, 1](res.num_elements())

@always_inline
fn accumulate_op[
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], t: Tensor[dtype]):
    @parameter
    fn vecmath[nelts: Int](idx: Int):
        res.store[nelts](idx, func[dtype, nelts](res.load[nelts](idx), t.load[nelts](idx)))

    vectorize[vecmath, nelts](t.num_elements())


@always_inline
fn accumulate_op[
    func: fn[dtype: DType, nelts: Int] (
        x: SIMD[dtype, nelts], y: SIMD[dtype, nelts]
    ) -> SIMD[dtype, nelts],
](inout res: Tensor[dtype], a: Scalar[dtype]):
    @parameter
    fn vecmath[nelts: Int](idx: Int):
        res.store[nelts](idx, func[dtype, nelts](res.load[nelts](idx), a))

    vectorize[vecmath, nelts](res.num_elements())


@always_inline
fn accumulate_grad(inout grad: Tensor[dtype], res_grad: Tensor[dtype]):
    # Accumulate gradient without checking for broadcasting
   accumulate_op[add](grad, res_grad)


@always_inline
fn accumulate_grad[
    grad_shape: TensorShape, res_grad_shape: TensorShape
](inout grad: Tensor[dtype], res_grad: Tensor[dtype]):
    @parameter
    if grad_shape == res_grad_shape:
        accumulate_op[add](grad, res_grad)
    elif res_grad_shape == TensorShape(1):
        accumulate_op[add](grad, res_grad[0])
    elif grad_shape != res_grad_shape:
        # Backward resulting gradient (res_grad) was formed from an operation that required broadcasting.
        # In order to accumulate res_grad to the gradient, the res_grad tensor needs to be unbroadcasted.
        # The following is equivalent to: Summing along the axes that were expanded during the broadcasting process.
        alias size = res_grad_shape.rank()
        alias strides_grad = broadcast_calculate_strides[
            size, grad_shape, res_grad_shape
        ]()

        @parameter
        fn vec_op[nelts: Int](i: Int):
            var index = get_real_index[size, strides_grad, res_grad_shape](i)
            grad[index] += res_grad.load[nelts](i).reduce_add()

        # TODO: Check how to vectorize this
        vectorize[vec_op, 1](res_grad.num_elements())


# ---- Transform functions -----
@always_inline
fn transpose_2D[t_shape: TensorShape](t: Tensor[dtype]) -> Tensor[dtype]:
    var t_new = Tensor[dtype](t_shape[1], t_shape[0])

    alias stride = t_shape[0]

    @parameter
    fn proc_row(i: Int):
        @parameter
        fn proc_column[nelts: Int](j: Int):
            t_new.data().offset(j * t_shape[0] + i).strided_store[width=nelts](
                t.load[nelts](i * t_shape[1] + j), stride
            )

        vectorize[proc_column, nelts](t.dim(1))

    parallelize[proc_row](t_shape[0])

    return t_new ^


@always_inline
fn transpose_2D[t_shape: TensorShape](t: UnsafePointer[Scalar[dtype]]) -> UnsafePointer[Scalar[dtype]]:
    var t_new = UnsafePointer[Scalar[dtype]].alloc(t_shape[1] * t_shape[0])

    alias stride = t_shape[0]

    @parameter
    fn proc_row(i: Int):
        @parameter
        fn proc_column[nelts: Int](j: Int):
            t_new.offset(j * t_shape[0] + i).strided_store[width=nelts](
                t.load[width=nelts](i * t_shape[1] + j), stride
            )

        vectorize[proc_column, nelts](t_shape[1])

    parallelize[proc_row](t_shape[0])

    return t_new


# ----- Reduction functions -----
@always_inline
fn reduce[
    op: fn[type: DType, simd_width: Int] (
        x: SIMD[type, simd_width], y: SIMD[type, simd_width]
    ) -> SIMD[type, simd_width],
    reduce_op: fn[type: DType, simd_width: Int] (x: SIMD[type, simd_width]) -> SIMD[
        type, 1
    ],
](t: Tensor[dtype], starting_value: SIMD[dtype, nelts]) -> Scalar[dtype]:
    var m: SIMD[dtype, nelts] = starting_value

    @parameter
    fn vecreduce[_nelts: Int](idx: Int):
        @parameter
        if _nelts == 1:
            m[0] = op(m[0], t.load[_nelts](idx)[0])
        else:
            m = op(m, t.load[nelts](idx))

    vectorize[vecreduce, nelts](t.num_elements())
    return reduce_op(m)


fn get_reduce_shape(t: TensorShape, axis: Int) -> TensorShape:
    var rank = t.rank()
    var new_shape = IndexList[MAX_RANK]()
    for i in range(rank):
        if i == axis:
            new_shape[i] = 1
        else:
            new_shape[i] = t[i]
    return TensorShape(rank=rank, shape=new_shape)


@always_inline
fn reduce[
    op: fn[type: DType, simd_width: Int] (
        x: SIMD[type, simd_width], y: SIMD[type, simd_width]
    ) -> SIMD[type, simd_width],
    reduce_op: fn[type: DType, simd_width: Int] (x: SIMD[type, simd_width]) -> SIMD[
        type, 1
    ],
](
    inout res: Tensor[dtype],
    t: Tensor[dtype],
    axis: Int,
    starting_value: SIMD[dtype, nelts],
):
    var strides = t.strides()

    @parameter
    fn parallel_reduce(i: Int):
        var m: SIMD[dtype, nelts] = starting_value

        var index_base = (i % strides[axis]) + (i // strides[axis]) * (
            strides[axis] * t.dim(axis)
        )

        @parameter
        fn axisreduce[_nelts: Int](j: Int):
            var index = index_base + j * strides[axis]
            if _nelts == 1:
                m[0] = op(
                    m[0],
                    t.data().offset(index).strided_load[width=_nelts](strides[axis])[0],
                )
            else:
                m = op(
                    m, t.data().offset(index).strided_load[width=nelts](strides[axis])
                )

        vectorize[axisreduce, nelts](t.dim(axis))

        res[i] = reduce_op(m)

    parallelize[parallel_reduce](t.num_elements() // t.dim(axis))

    _ = strides


@always_inline
fn _reduce_sum[
    type: DType, simd_width: Int
](x: SIMD[type, simd_width]) -> Scalar[type]:
    return x.reduce_add()


@always_inline
fn tsum(t: Tensor[dtype]) -> Scalar[dtype]:
    var starting_value = 0
    return reduce[add, _reduce_sum](t, starting_value)


@always_inline
fn tmean(t: Tensor[dtype]) -> Scalar[dtype]:
    return tsum(t) / t.num_elements()


@always_inline
fn tstd(t: Tensor[dtype]) -> Scalar[dtype]:
    var mu: Scalar[dtype] = tmean(t)
    var variance: Scalar[dtype] = 0

    @parameter
    fn vecvar[nelts: Int](idx: Int):
        var diff = t.load[nelts](idx) - mu
        variance += (diff * diff).reduce_add()

    vectorize[vecvar, nelts](t.num_elements())

    return sqrt(variance / t.num_elements())


@always_inline
fn tsum(inout res: Tensor[dtype], t: Tensor[dtype], axis: Int):
    var starting_value = 0
    reduce[add, _reduce_sum](res, t, axis, starting_value)


@always_inline
fn tmean(inout res: Tensor[dtype], t: Tensor[dtype], axis: Int):
    var num_elements_axis: Scalar[dtype] = t.dim(axis)
    tsum(res, t, axis)
    accumulate_op[div](res, num_elements_axis)


@always_inline
fn tstd(inout res: Tensor[dtype], t: Tensor[dtype], axis: Int):
    var mu = Tensor[dtype](get_reduce_shape(t.shape(), axis))
    tmean(mu, t, axis)

    var num_elements_axis: Scalar[dtype] = t.dim(axis)
    var strides = t.strides()
    var strides_mu = mu.strides()

    @parameter
    fn get_t_index(
        i: Int, j: Int, axis: Int, shape: TensorShape, strides: IndexList[MAX_RANK]
    ) -> Int:
        var index_res = 0
        for k in range(shape.rank()):
            if k == axis:
                index_res += j * strides[k]
            else:
                index_res += (i % shape[k]) * strides[k]
        return index_res

    @parameter
    fn get_mu_index(
        i: Int, axis: Int, shape: TensorShape, strides: IndexList[MAX_RANK]
    ) -> Int:
        var index_res = 0
        for k in range(shape.rank()):
            if k != axis:
                index_res += (i % shape[k]) * strides[k]
        return index_res

    for i in range(t.num_elements() // t.dim(axis)):
        var mu_index = get_mu_index(i, axis, mu.shape(), strides_mu)

        @parameter
        fn vecvar[nelts: Int](j: Int):
            var t_index = get_t_index(i, j, axis, t.shape(), strides)
            var diff = t.load[nelts](t_index) - mu[mu_index]
            res[i] += (diff * diff).reduce_add()

        vectorize[vecvar, nelts](t.dim(axis))

        res[i] /= num_elements_axis

    _ = (strides, strides_mu)
    elwise_transform[sqrt](res)


@always_inline
fn _reduce_max[
    type: DType, simd_width: Int
](x: SIMD[type, simd_width]) -> Scalar[type]:
    return x.reduce_max()


@always_inline
fn tmax(t: Tensor[dtype]) -> Scalar[dtype]:
    var starting_value = min_finite[dtype]()
    return reduce[max, _reduce_max](t, starting_value)


@always_inline
fn tmax(inout res: Tensor[dtype], t: Tensor[dtype], axis: Int):
    var starting_value = min_finite[dtype]()
    reduce[max, _reduce_max](res, t, axis, starting_value)


# @always_inline
# fn transpose[
#     dtype: DType, nelts: Int
# ](t: Tensor[dtype], dim_0: Int, dim_1: Int) -> Tensor[dtype]:
#     """
#     Create a new tensor transposing dim_0 and dim_1.
#     """
#     var axes = DynamicVector[Int](t.rank())

#     for i in range(t.rank()):
#         if i == dim_0:
#             axes.push_back(dim_1)
#         elif i == dim_1:
#             axes.push_back(dim_0)
#         else:
#             axes.push_back(i)

#     return transpose[dtype, nelts](t, axes)


# @always_inline
# fn transpose(inout res: Tensor[dtype], t: Tensor[dtype]):
#     """
#     Create a new transposed tensor of the given tensor t.
#     """
#     var axes = DynamicVector[Int](capacity=t.rank())

#     for i in range(t.rank() - 1, -1, -1):
#         axes.push_back(i)

#     var axes_shape = TensorShape(axes)

#     transpose(res, t, axes_shape)


# @always_inline
# fn transpose(t: Tensor[dtype], axes: DynamicVector[Int]) -> Tensor[dtype]:
#     var new_shape = DynamicVector[Int](capacity=t.rank())
#     for i in range(t.rank()):
#         new_shape.push_back(t.dim(axes[i]))

#     var t_new_shape = TensorShape(new_shape)
#     var t_new = Tensor[dtype](t_new_shape)

#     transpose(t_new, t, t_new_shape)

#     return t_new


@always_inline
fn get_transpose_shape(t: TensorShape, axes: TensorShape) -> TensorShape:
    var rank = t.rank()
    var new_shape = IndexList[MAX_RANK]()

    for i in range(rank):
        new_shape[i] = t[axes[i]]

    return TensorShape(rank=rank, shape=new_shape)


@always_inline
fn transpose(t: Tensor[dtype], axes: TensorShape) -> Tensor[dtype]:
    var t_new_shape = get_transpose_shape(t.shape(), axes)
    var t_new = Tensor[dtype](t_new_shape)

    transpose(t_new, t, axes)

    return t_new ^


@always_inline
fn transpose(inout res: Tensor[dtype], t: Tensor[dtype], axes: TensorShape):
    """
    Create a new transposed tensor of the given tensor t.
    """
    # NOTE: The rank of of the t tensor should be 2 or more
    # NOTE: Axes should be the same size as the rank of t

    var original_strides = t.strides()
    var transposed_strides = res.strides()

    var position_of_last_rank_new_shape = 0

    # Get position of where the last dim of the old shape is in the new shape
    for i in range(axes.rank()):
        if t.rank() - 1 == axes[i]:
            position_of_last_rank_new_shape = i

    @parameter
    fn p_transpose(i: Int):
        @parameter
        fn v_transpose[nelts: Int](j: Int):
            var new_index = 0
            var original_index = i * t.dim(t.rank() - 1) + j
            var linear_index = original_index
            for k in range(t.rank()):
                # axes tells us the position of where the dim in the transposed shape is located in the original shape
                var stride = original_strides[axes[k]]
                var index = linear_index // stride % t.dim(axes[k])

                new_index += index * transposed_strides[k]

            res.data().offset(new_index).strided_store[width=nelts](
                t.load[nelts](original_index),
                transposed_strides[position_of_last_rank_new_shape],
            )

        vectorize[v_transpose, nelts](t.dim(t.rank() - 1))

    parallelize[p_transpose](t.num_elements() // t.dim(t.rank() - 1))

    _ = (original_strides, transposed_strides)


# # NOTE: This function can be used for later for optimziation (Many operations in gpu is preferred to pad the tensors when using conv or matmul operations)
# # TODO: Deprecate this function, as it is not used anymore
# @always_inline
# fn pad_zeros[
#     dtype: DType, nelts: Int
# ](t: Tensor[dtype], pad_with: DynamicVector[Int]) -> Tensor[dtype]:
#     """
#     Pad a tensor with zeros along the specified axes of an N dimensional tensor.
#     Number of values padded to the edges of each axis.
#     Example: ((before_1, after_1), ... (before_N, after_N)).
#     """

#     # NOTE: The rank of of the t tensor should be equal to the size of pad_with devided by 2.
#     # As pad_with contains (before, after) number of paddings for each axis.
#     var new_shape = DynamicVector[Int](t.rank())
#     for i in range(t.rank()):
#         new_shape.push_back(t.dim(i) + pad_with[i * 2] + pad_with[i * 2 + 1])
#     var t_new = Tensor[dtype](new_shape)

#     var original_strides = t.strides()
#     var result_strides = t_new.strides()

#     # Parallelize over the first axis
#     # NOTE: Possible dynamically choose the axis to parallelize over
#     @parameter
#     fn p_pad(i: Int):
#         for j in range(t.num_elements() // t.dim(0)):
#             var original_index = i * original_strides[0] + j

#             # Padding contribution of the first dimention
#             var dest_index = (i + pad_with[0]) * result_strides[0]

#             # Calculate the contribution from each dimension
#             var remaining_index = j % original_strides[0]
#             for dim in range(1, t.rank()):
#                 var stride = original_strides[dim]
#                 var index = remaining_index // stride
#                 remaining_index = remaining_index % stride

#                 dest_index += (index + pad_with[dim * 2]) * result_strides[dim]

#             # TODO: figure out vectorization
#             t_new[dest_index] = t[original_index]

#     parallelize[p_pad](t.dim(0))

#     _ = (original_strides, result_strides)

#     return t_new
