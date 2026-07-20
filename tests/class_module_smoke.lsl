load modules.sample
from modules.sample load multiply as module_multiply
from modules.sample load name as module_name

tool = sample.Tool(6)
print sample.name, sample.multiply(4), module_name, module_multiply(5)
print tool.double(), type(sample.Tool), type(tool)
