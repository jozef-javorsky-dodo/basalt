from algorithm import vectorize, parallelize
from math import exp, pow, max, min, abs
from math.limit import min_finite, max_finite

from basalt import Tensor, TensorShape
from basalt.utils.tensorutils import elwise_transform
from basalt.autograd.attributes import Attribute, AttributeVector


@value
struct SIGMOID:
    @staticmethod
    fn result_shape(t1_shape: TensorShape) -> TensorShape:
        return t1_shape

    @staticmethod
    @always_inline
    fn sigmoid[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return 1 / (1 + exp(-x))

    @staticmethod
    @always_inline
    fn sidmoid_bw[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return Self.sigmoid(x) * (1 - Self.sigmoid(x))

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        """Forward operation of sigmoid."""
        elwise_transform[Self.sigmoid](res, t1)

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of sigmoid."""
        # d(sigmod(x))/dx = sigmoid(x) * (1 - sigmoid(x))
        var res_grad = Tensor[dtype](ug_shape)

        @parameter
        fn vec_sigmoid_bw[nelts: Int](idx: Int):
            res_grad.store[nelts](
                idx,
                Self.sidmoid_bw(t1.load[nelts](idx)) * ug.load[nelts](idx),
            )

        vectorize[vec_sigmoid_bw, nelts](ug_shape.num_elements())

        return res_grad ^


struct RELU:
    @staticmethod
    fn result_shape(t1_shape: TensorShape) -> TensorShape:
        return t1_shape

    @staticmethod
    @always_inline
    fn relu[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        # x if x > 0 else 0
        return (x > 0).select(x, 0)

    @staticmethod
    @always_inline
    fn relu_bw[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        # 1 if x > 0 else 0
        return (x > 0).select[type](1, 0)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        """Forward operation of relu."""
        elwise_transform[Self.relu](res, t1)

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of relu."""
        # d(relu(x))/dx = 1 if x > 0 else 0. We also give 0 to x = 0 instead of undefined.
        var res_grad = Tensor[dtype](ug_shape)

        @parameter
        fn vec_relu_bw[nelts: Int](idx: Int):
            res_grad.store[nelts](
                idx, Self.relu_bw(t1.load[nelts](idx)) * ug.load[nelts](idx)
            )

        vectorize[vec_relu_bw, nelts](ug_shape.num_elements())

        return res_grad ^


struct TANH:
    @staticmethod
    fn result_shape(t1_shape: TensorShape) -> TensorShape:
        return t1_shape

    @staticmethod
    @always_inline
    fn tanh[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return (exp(x) - exp(-x)) / (exp(x) + exp(-x))

    @staticmethod
    @always_inline
    fn tanh_bw[
        type: DType, simd_width: Int
    ](x: SIMD[type, simd_width]) -> SIMD[type, simd_width]:
        return 1 - pow(Self.tanh(x), 2)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        """Forward operation of tanh."""
        elwise_transform[Self.tanh](res, t1)

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of tanh."""
        # d(tanh(x))/dx = 1 - tanh(x) ** 2
        var res_grad = Tensor[dtype](ug_shape)

        @parameter
        fn vec_tanh_bw[nelts: Int](idx: Int):
            res_grad.store[nelts](
                idx, Self.tanh_bw(t1.load[nelts](idx)) * ug.load[nelts](idx)
            )

        vectorize[vec_tanh_bw, nelts](ug_shape.num_elements())

        return res_grad ^


struct CLIP:
    @staticmethod
    fn result_shape(t_shape: TensorShape) -> TensorShape:
        return t_shape

    @staticmethod
    fn forward[
        t_shape: TensorShape, attributes: AttributeVector
    ](inout res: Tensor[dtype], t: Tensor[dtype]):
        """
        Forward pass of the clip operation.
        """
        alias min_attr = attributes["min"]
        alias max_attr = attributes["max"]

        var min_val = min_attr.value().to_scalar[dtype]() if min_attr else min_finite[
            dtype
        ]()
        var max_val = max_attr.value().to_scalar[dtype]() if max_attr else max_finite[
            dtype
        ]()

        @parameter
        fn vec_clip[nelts: Int](i: Int):
            res.store[nelts](i, t.load[nelts](i).min(max_val).max(min_val))

        vectorize[vec_clip, nelts, size = t_shape.num_elements()]()

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t_shape: TensorShape,
        attributes: AttributeVector = AttributeVector(),
    ](ug: Tensor[dtype], t: Tensor[dtype]) -> Tensor[dtype]:
        """Backward operation of clip."""
        alias min_attr = attributes["min"]
        alias max_attr = attributes["max"]

        var min_val = min_attr.value().to_scalar[dtype]() if min_attr else min_finite[
            dtype
        ]()
        var max_val = max_attr.value().to_scalar[dtype]() if max_attr else max_finite[
            dtype
        ]()

        var res_grad = Tensor[dtype](t_shape)

        @parameter
        fn vec_clip_bw[nelts: Int](i: Int):
            var val = t.load[nelts](i)
            res_grad.store[nelts](
                i,
                ((val >= min_val) * (val <= max_val)).select(ug.load[nelts](i), 0),
            )

        vectorize[vec_clip_bw, nelts, size = t_shape.num_elements()]()

        return res_grad ^


struct SQUEEZE:
    @staticmethod
    fn result_shape(t1_shape: TensorShape, attributes: AttributeVector) -> TensorShape:
        var dim = attributes["dims"]
        var dims_to_squeeze = dim.value().to_shape() if dim else TensorShape()

        var new_shape = List[Int]()
        for i in range(t1_shape.rank()):
            if (not dim and t1_shape[i] == 1) or (
                i in dims_to_squeeze and t1_shape[i] == 1
            ):
                continue
            new_shape.append(t1_shape[i])

        return TensorShape(new_shape)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
        attributes: AttributeVector,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        memcpy(res.data(), t1.data(), t1.num_elements())

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        var res_grad = Tensor[dtype](t1_shape)
        memcpy(res_grad.data(), ug.data(), ug.num_elements())
        return res_grad ^


struct UNSQUEEZE:
    @staticmethod
    fn result_shape(t1_shape: TensorShape, attributes: AttributeVector) -> TensorShape:
        var dim = attributes["dims"]
        var dims_to_squeeze = dim.value().to_shape() if dim else TensorShape()

        # Position in the expanded dims where the new dim (or dims) is placed.
        var new_rank = t1_shape.rank() + dims_to_squeeze.rank()

        var new_shape = List[Int]()
        var j = 0
        for i in range(new_rank):
            if i in dims_to_squeeze or i - new_rank in dims_to_squeeze:
                new_shape.append(1)
            else:
                new_shape.append(t1_shape[j])
                j += 1

        return TensorShape(new_shape)

    @staticmethod
    fn forward[
        t1_shape: TensorShape,
        attributes: AttributeVector,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        memcpy(res.data(), t1.data(), t1.num_elements())

    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        var res_grad = Tensor[dtype](t1_shape)
        memcpy(res_grad.data(), ug.data(), ug.num_elements())
        return res_grad ^


struct SLICE:
    @staticmethod
    fn adjust_boundary(slice: Int, dim_size: Int) -> Int:
        # Adjust negative indices & ensure they are within bounds.
        var s = slice if slice >= 0 else dim_size + slice
        return max(min(s, dim_size), 0)
    
    @staticmethod
    fn default_starts(shape: TensorShape) -> List[Int]:
        var starts = List[Int]()
        for i in range(shape.rank()):
            starts.append(0)
        return starts^

    @staticmethod
    fn default_ends(shape: TensorShape) -> List[Int]:
        var ends = List[Int]()
        for i in range(shape.rank()):
            ends.append(shape[i])
        return ends^

    @staticmethod
    fn default_steps(shape: TensorShape) -> List[Int]:
        var steps = List[Int]()
        for i in range(shape.rank()):
            steps.append(1)
        return steps^
    
    @staticmethod
    fn default_axes(shape: TensorShape) -> List[Int]:
        # NOTE: axes can't be negative
        var axes = List[Int]()
        for i in range(shape.rank()):
            axes.append(i)
        return axes^

    @staticmethod
    fn result_shape(t1_shape: TensorShape, attributes: AttributeVector) -> TensorShape:
        # NOTE: Starts and ends have to be of the same size
        # NOTE: If axes not provided, starts and ends have to be of the same size as t1_shape
        var starts = attributes["starts"].value().to_shape()
        var ends = attributes["ends"].value().to_shape()
        var steps = attributes["steps"].value().to_shape() if attributes["steps"] else Self.default_steps(starts)
        var axes = attributes["axes"].value().to_shape() if attributes["axes"] else Self.default_axes(t1_shape)

        var new_shape = t1_shape
        for i in range(starts.rank()):
            var axis = axes[i]
            new_shape[axis] = len(range(
                start = Self.adjust_boundary(starts[i], t1_shape[axis]),
                end = Self.adjust_boundary(ends[i], t1_shape[axis]),
                step = steps[i]
            ))

        return new_shape

    @staticmethod
    fn reorder_positions[id: Int](original: TensorShape, axes: TensorShape, t1_shape: TensorShape) -> List[Int]:
        # Reorder the starts (id=0), ends (id=1) or steps (id=2) to match the order of the axes
        var updated: List[Int]

        @parameter
        if id == 0: updated = Self.default_starts(t1_shape)
        elif id == 1: updated = Self.default_ends(t1_shape)
        else: updated = Self.default_steps(t1_shape)
    
        for i in range(axes.rank()):
            var axis = axes[i]
            updated[axis] = original[i] if id == 2 else Self.adjust_boundary(original[i], t1_shape[axis])

        return updated^

    # For now you can't have recursive function as parameter functions. And from testing it seems a recursive function is almost the same speed as doing multiple nested for loops (if they aren't flattened, nested for loops can be flattened).
    @staticmethod
    fn recursive_iters_slice[
        backward_op: Bool = False,
    ](
        inout res: Tensor[dtype],
        t1: Tensor[dtype],
        last_dims: Int,
        original_shape: TensorShape,
        shape: TensorShape,
        steps: List[Int],
        starts: List[Int],
        ends: List[Int],
        position: Int, 
        last_position: Int,
        idx: Int,
        idx_original: Int,
    ):

        var strides = shape.strides()
        var t1_strides = original_shape.strides()

        var idx_temp = idx
        var idx_original_temp = starts[position] * t1_strides[position] + idx_original

        if position == last_position + 1:
            var position = shape.rank() - 1
            # Work on the last dimensions
            var temp_idx = idx_original_temp
            @parameter
            fn v_slice[nelts: Int](k : Int):
                var idx_contiguous = idx_temp + k
                @parameter
                if not backward_op:
                    if steps[position] == 1:
                        res.store[nelts](idx_contiguous, t1.load[nelts](temp_idx))
                    else:
                        res.store[nelts](idx_contiguous, t1.data().offset(temp_idx).simd_strided_load[nelts](t1_strides[position] * steps[position]))
                else:
                    if steps[position] == 1:
                        res.store[nelts](temp_idx, t1.load[nelts](idx_contiguous))
                    else:
                        res.data().offset(temp_idx).simd_strided_store[nelts](t1.load[nelts](idx_contiguous), t1_strides[position] * steps[position])
    
                temp_idx += steps[position] * t1_strides[position] * nelts

            vectorize[v_slice, nelts](last_dims)

            return 

        for i in range(shape[position]):
            Self.recursive_iters_slice[backward_op](res, t1, last_dims,original_shape, shape, steps, starts, ends, position + 1, last_position, idx_temp, idx_original_temp)

            idx_temp += strides[position]
            idx_original_temp += steps[position] * t1_strides[position]

    @staticmethod
    fn slice_kernel[backward_op: Bool = False](inout res: Tensor[dtype], t1: Tensor[dtype], main_shape: TensorShape, original_shape: TensorShape, t1_strides: StaticIntTuple[8], steps: List[Int], starts: List[Int], ends: List[Int]):
        # Get the dimensions for vectorization
        var last_dims = 1
        var positions_to_skip = 0
        for i in range(main_shape.rank() - 1, -1, -1):
            if steps[i] != 1 and i != main_shape.rank() - 1:
                break
            last_dims *= main_shape[i]
            positions_to_skip += 1
            if starts[i] != 0 or ends[i] != original_shape[i] or steps[i] != 1:
                break
        # Get the dimensions for the first loop
        var first_dims = 1
        var start_position = 0
        for i in range(main_shape.rank() - positions_to_skip):
            if steps[i] != 1 or starts[i] != 0 or ends[i] != original_shape[i]:
                break
            first_dims *= main_shape[i]
            start_position += 1


        # Copy the data. P.S if the slice dimensions are small, this kernel can be slow (because the worst case for the while loop happens more times).
        var middle_dims = main_shape.num_elements() // last_dims // first_dims
        @parameter
        fn p_slice(i: Int):
            Self.recursive_iters_slice[backward_op](res, t1, last_dims, original_shape, main_shape, steps, starts, ends, start_position, main_shape.rank() - 1 - positions_to_skip, 
            i * middle_dims * last_dims, i * t1_strides[start_position - 1])

        parallelize[p_slice](first_dims)
    
    @staticmethod
    fn forward[
        t1_shape: TensorShape,
        attributes: AttributeVector,
    ](inout res: Tensor[dtype], t1: Tensor[dtype]):
        alias axes = attributes["axes"].value().to_shape() if attributes["axes"] else Self.default_axes(t1_shape)
        alias starts = Self.reorder_positions[0](attributes["starts"].value().to_shape(), axes, t1_shape)
        alias ends = Self.reorder_positions[1](attributes["ends"].value().to_shape(), axes, t1_shape)
        alias steps = Self.reorder_positions[2](attributes["steps"].value().to_shape(), axes, t1_shape) if attributes["steps"] else Self.default_steps(t1_shape)

        alias res_shape = Self.result_shape(t1_shape, attributes)
        
        alias strides = t1_shape.strides()

        Self.slice_kernel(res, t1, res_shape, t1_shape, strides, steps, starts, ends)


    @staticmethod
    fn backward[
        ug_shape: TensorShape,
        t1_shape: TensorShape,
        attributes: AttributeVector = AttributeVector(),
    ](ug: Tensor[dtype], t1: Tensor[dtype]) -> Tensor[dtype]:
        alias axes = attributes["axes"].value().to_shape() if attributes["axes"] else Self.default_axes(t1_shape)
        alias starts = Self.reorder_positions[0](attributes["starts"].value().to_shape(), axes, t1_shape)
        alias ends = Self.reorder_positions[1](attributes["ends"].value().to_shape(), axes, t1_shape)
        alias steps = Self.reorder_positions[2](attributes["steps"].value().to_shape(), axes, t1_shape) if attributes["steps"] else Self.default_steps(t1_shape)

        alias strides = t1_shape.strides()

        var res_grad = Tensor[dtype](t1_shape)
        
        Self.slice_kernel[True](res_grad, ug, ug_shape, t1_shape, strides, steps, starts, ends)
        
        return res_grad ^