from basalt import dtype, nelts
from basalt.autograd import OP
from basalt.autograd.attributes import AttributeVector, Attribute
from basalt.autograd.ops.mlops import SIGMOID, RELU, TANH, CLIP, SQUEEZE, UNSQUEEZE
from basalt.nn import Tensor, TensorShape
from basalt.utils.tensorutils import fill

from tests import assert_tensors_equal, test_unary_op, test_unary_op_backward


fn test_SIGMOID() raises:
    alias t1_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)

    var expected = Tensor[dtype](2, 3)
    fill(expected, 0.5)

    test_unary_op[OP.SIGMOID, t1_shape](t1, expected)


fn test_backward_SIGMOID() raises:
    alias t1_shape = TensorShape(2, 3)
    alias ug_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    var ug: Tensor[dtype] = Tensor[dtype](ug_shape)
    fill(ug, 5.0)

    var expected_grad = Tensor[dtype](2, 3)
    fill(
        expected_grad, 5.0 * 0.25
    )  # 0.25 = d(sigmoid(0))/dx = sigmoid(0) * (1 - sigmoid(0))

    test_unary_op_backward[OP.SIGMOID, t1_shape, ug_shape](t1, ug, expected_grad)


fn test_RELU() raises:
    alias t1_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    # TODO: When tensors can do slices, this could be changed to two fill functions.
    for i in range(3):
        t1[i] = 3
    for i in range(3, 6):
        t1[i] = -3

    var expected = Tensor[dtype](2, 3)
    for i in range(3):
        expected[i] = 3
    for i in range(3, 6):
        expected[i] = 0

    test_unary_op[OP.RELU, t1_shape](t1, expected)


fn test_backward_RELU() raises:
    alias t1_shape = TensorShape(2, 3)
    alias ug_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    var ug: Tensor[dtype] = Tensor[dtype](ug_shape)
    for i in range(3):
        t1[i] = 3
    for i in range(3, 6):
        t1[i] = -3
    fill(ug, 5.0)

    var expected_grad = Tensor[dtype](2, 3)
    for i in range(3):
        expected_grad[i] = 1 * 5.0  # 1 = d(relu(3))/dx
    for i in range(3, 6):
        expected_grad[i] = 0 * 5.0  # 0 = d(relu(-3))/dx

    test_unary_op_backward[OP.RELU, t1_shape, ug_shape](t1, ug, expected_grad)


fn test_TANH() raises:
    alias t1_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)

    var expected = Tensor[dtype](2, 3)
    fill(expected, 0.0)

    test_unary_op[OP.TANH, t1_shape](t1, expected)


fn test_backward_TANH() raises:
    alias t1_shape = TensorShape(2, 3)
    alias ug_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    var ug: Tensor[dtype] = Tensor[dtype](ug_shape)
    fill(ug, 5.0)

    var expected_grad = Tensor[dtype](2, 3)
    fill(expected_grad, 5.0 * 1.0)  # 1.0 = d(tanh(0))/dx = 1 - tanh(0)^2

    test_unary_op_backward[OP.TANH, t1_shape, ug_shape](t1, ug, expected_grad)


fn test_CLIP() raises:
    alias t1_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    for i in range(6):
        t1[i] = i - 3

    # Clip without min and max
    var expected_no = t1
    test_unary_op[OP.CLIP, t1_shape](t1, expected_no)

    # Clip with min
    alias min_attr = Attribute("min", -1.1)
    var expected_min = Tensor[dtype](2, 3)
    for i in range(6):
        var val = Scalar[dtype](i - 3)
        expected_min[i] = val if (val > -1.1) else -1.1
    test_unary_op[OP.CLIP, t1_shape, AttributeVector(min_attr)](t1, expected_min)

    # Clip with max
    alias max_attr = Attribute("max", 1.1)
    var expected_max = Tensor[dtype](2, 3)
    for i in range(6):
        var val = Scalar[dtype](i - 3)
        expected_max[i] = val if (val < 1.1) else 1.1
    test_unary_op[OP.CLIP, t1_shape, AttributeVector(max_attr)](t1, expected_max)

    # Clip with min and max
    var expected = Tensor[dtype](2, 3)
    for i in range(6):
        var val = Scalar[dtype](i - 3)
        if val < -1.1:
            expected[i] = -1.1
        elif val > 1.1:
            expected[i] = 1.1
        else:
            expected[i] = val
    test_unary_op[OP.CLIP, t1_shape, AttributeVector(min_attr, max_attr)](t1, expected)


fn test_backward_CLIP() raises:
    alias t1_shape = TensorShape(2, 3)
    alias ug_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    for i in range(6):
        t1[i] = i - 3
    var ug: Tensor[dtype] = Tensor[dtype](ug_shape)
    fill(ug, 5.0)

    # Clip without min and max
    var expected_no = ug
    test_unary_op_backward[OP.CLIP, t1_shape, ug_shape](t1, ug, expected_no)

    # Clip with min
    alias min_attr = AttributeVector(Attribute("min", -1.1))
    var expected_min = Tensor[dtype](2, 3)
    for i in range(6):
        var val = Scalar[dtype](i - 3)
        expected_min[i] = 5.0 if (val > -1.1) else 0.0
    test_unary_op_backward[OP.CLIP, t1_shape, ug_shape, min_attr](t1, ug, expected_min)

    # Clip with max
    alias max_attr = AttributeVector(Attribute("max", 1.1))
    var expected_max = Tensor[dtype](2, 3)
    for i in range(6):
        var val = Scalar[dtype](i - 3)
        expected_max[i] = 5.0 if (val < 1.1) else 0.0
    test_unary_op_backward[OP.CLIP, t1_shape, ug_shape, max_attr](t1, ug, expected_max)

    # Clip with min and max
    alias attrs = AttributeVector(Attribute("min", -1.1), Attribute("max", 1.1))
    var expected = Tensor[dtype](2, 3)
    for i in range(6):
        var val = Scalar[dtype](i - 3)
        if val < -1.1 or val > 1.1:
            expected[i] = 0.0
        else:
            expected[i] = 5.0
    test_unary_op_backward[OP.CLIP, t1_shape, ug_shape, attrs](t1, ug, expected)


fn test_SQUEEZE() raises:
    alias t1_shape = TensorShape(1, 2, 1, 3, 1)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    fill(t1, 5.0)

    # Test with no dims
    var expected = Tensor[dtype](2, 3)
    fill(expected, 5.0)
    test_unary_op[OP.SQUEEZE, t1_shape](t1, expected)

    # Test with one dim
    expected = Tensor[dtype](1, 2, 1, 3)
    fill(expected, 5.0)
    test_unary_op[
        OP.SQUEEZE, t1_shape, AttributeVector(Attribute("dims", TensorShape(4)))
    ](t1, expected)

    expected = Tensor[dtype](1, 2, 3, 1)
    fill(expected, 5.0)
    test_unary_op[
        OP.SQUEEZE, t1_shape, AttributeVector(Attribute("dims", TensorShape(2)))
    ](t1, expected)

    # Test with multiple dims
    expected = Tensor[dtype](1, 2, 3)
    fill(expected, 5.0)
    test_unary_op[
        OP.SQUEEZE, t1_shape, AttributeVector(Attribute("dims", TensorShape(2, 4)))
    ](t1, expected)


fn test_backward_SQUEEZE() raises:
    alias t1_shape = TensorShape(2, 1, 3, 1)
    alias ug_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    fill(t1, 5.0)
    var ug: Tensor[dtype] = Tensor[dtype](ug_shape)
    fill(ug, 5.0)

    var expected_grad = Tensor[dtype](2, 1, 3, 1)
    fill(expected_grad, 5.0)

    test_unary_op_backward[OP.SQUEEZE, t1_shape, ug_shape](t1, ug, expected_grad)


fn test_UNSQUEEZE() raises:
    # UNSQUEEZE here is more similar to jax expand_dims
    alias t1_shape = TensorShape(2, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    fill(t1, 5.0)

    var expected = Tensor[dtype](2, 1, 3, 1)
    fill(expected, 5.0)
    test_unary_op[
        OP.UNSQUEEZE, t1_shape, AttributeVector(Attribute("dims", TensorShape(1, 3)))
    ](t1, expected)

    expected = Tensor[dtype](2, 1, 3)
    fill(expected, 5.0)

    test_unary_op[
        OP.UNSQUEEZE, t1_shape, AttributeVector(Attribute("dims", TensorShape(1)))
    ](t1, expected)

    expected = Tensor[dtype](1, 2, 3)
    fill(expected, 5.0)
    test_unary_op[
        OP.UNSQUEEZE, t1_shape, AttributeVector(Attribute("dims", TensorShape(-3)))
    ](t1, expected)

    expected = Tensor[dtype](2, 1, 3, 1)
    fill(expected, 5.0)
    test_unary_op[
        OP.UNSQUEEZE, t1_shape, AttributeVector(Attribute("dims", TensorShape(-1, -3)))
    ](t1, expected)


fn test_backward_UNSQUEEZE() raises:
    alias t1_shape = TensorShape(2, 3)
    alias ug_shape = TensorShape(2, 1, 3)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    fill(t1, 5.0)
    var ug: Tensor[dtype] = Tensor[dtype](ug_shape)
    fill(ug, 5.0)

    var expected_grad = Tensor[dtype](2, 3)
    fill(expected_grad, 5.0)

    test_unary_op_backward[OP.UNSQUEEZE, t1_shape, ug_shape](t1, ug, expected_grad)


fn test_SLICE() raises:
    alias t1_shape = TensorShape(3, 4, 5)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    for i in range(t1.num_elements()):
        t1[i] = i
    
    alias slice = Slice(1, 3, 1)

    # dim = 0
    var expected_0 = Tensor[dtype](2, 4, 5)
    for i in range(2):
        for j in range(4):
            for k in range(5):
                expected_0[i*4*5 + j*5 + k] = (i + 1) * 4 * 5 + j * 5 + k

    test_unary_op[
        OP.SLICE, t1_shape, AttributeVector(
            Attribute("slice", StaticIntTuple[3](slice.start, slice.end, slice.step)),
            Attribute("dim", 0)
        )
    ](t1, expected_0)

    # dim = 1
    var expected_1 = Tensor[dtype](3, 2, 5)
    for i in range(3):
        for j in range(2):
            for k in range(5):
                expected_1[i*2*5 + j*5 + k] = i * 4 * 5 + (j + 1) * 5 + k

    test_unary_op[
        OP.SLICE, t1_shape, AttributeVector(
            Attribute("slice", StaticIntTuple[3](slice.start, slice.end, slice.step)),
            Attribute("dim", 1)
        )
    ](t1, expected_1)

    # dim = 2
    var expected_2 = Tensor[dtype](3, 4, 2)
    for i in range(3):
        for j in range(4):
            for k in range(2):
                expected_2[i*4*2 + j*2 + k] = i * 4 * 5 + j * 5 + (k + 1)
        
    test_unary_op[
        OP.SLICE, t1_shape, AttributeVector(
            Attribute("slice", StaticIntTuple[3](slice.start, slice.end, slice.step)),
            Attribute("dim", 2)
        )
    ](t1, expected_2)


fn test_SLICE_step() raises:
    alias slice = Slice(1, 6, 2)

    # dim = 0
    alias t0_shape = TensorShape(10, 2, 2)
    var t0: Tensor[dtype] = Tensor[dtype](t0_shape)
    for i in range(t0.num_elements()):
        t0[i] = i

    var expected_0 = Tensor[dtype](3, 2, 2)
    for i in range(3):
        for j in range(2):
            for k in range(2):
                expected_0[i*2*2 + j*2 + k] = (i*2 + 1) * 2 * 2 + j * 2 + k

    test_unary_op[
        OP.SLICE, t0_shape, AttributeVector(
            Attribute("slice", StaticIntTuple[3](slice.start, slice.end, slice.step)),
            Attribute("dim", 0)
        )
    ](t0, expected_0)

    # dim = 1
    alias t1_shape = TensorShape(2, 10, 2)
    var t1: Tensor[dtype] = Tensor[dtype](t1_shape)
    for i in range(t1.num_elements()):
        t1[i] = i

    var expected_1 = Tensor[dtype](2, 3, 2)
    for i in range(2):
        for j in range(3):
            for k in range(2):
                expected_1[i*3*2 + j*2 + k] = i * 10 * 2 + (j*2 + 1) * 2 + k

    test_unary_op[
        OP.SLICE, t1_shape, AttributeVector(
            Attribute("slice", StaticIntTuple[3](slice.start, slice.end, slice.step)),
            Attribute("dim", 1)
        )
    ](t1, expected_1)

    # dim = 2
    alias t2_shape = TensorShape(2, 2, 10)
    var t2: Tensor[dtype] = Tensor[dtype](t2_shape)
    for i in range(t2.num_elements()):
        t2[i] = i

    var expected_2 = Tensor[dtype](2, 2, 3)
    for i in range(2):
        for j in range(2):
            for k in range(3):
                expected_2[i*2*3 + j*3 + k] = i * 2 * 10 + j * 10 + (k*2 + 1)

    test_unary_op[
        OP.SLICE, t2_shape, AttributeVector(
            Attribute("slice", StaticIntTuple[3](slice.start, slice.end, slice.step)),
            Attribute("dim", 2)
        )
    ](t2, expected_2)


fn main():
    try:
        test_SIGMOID()
        test_RELU()
        test_TANH()
        test_CLIP()
        test_SQUEEZE()
        test_UNSQUEEZE()
        test_SLICE()
        test_SLICE_step()
    except e:
        print("[ERROR] Error in forward mlops")
        print(e)
        return

    # try:
    #     test_backward_SIGMOID()
    #     test_backward_RELU()
    #     test_backward_TANH()
    #     test_backward_CLIP()
    #     test_backward_SQUEEZE()
    #     test_backward_UNSQUEEZE()
    # except e:
    #     print("[ERROR] Error in backward mlops")
    #     print(e)
    #     return
