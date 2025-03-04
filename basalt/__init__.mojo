from .autograd import Graph, Symbol, OP
from .nn import Tensor, TensorShape
from sys.info import simdwidthof
from basalt.utils.collection import Collection

alias dtype = DType.float32
alias nelts = 2 * simdwidthof[dtype]()
alias seed = 42
alias epsilon = 1e-12
