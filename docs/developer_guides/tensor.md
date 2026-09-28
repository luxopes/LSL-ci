# Knihovna tensor

`load tensor`

Husté CPU tenzory nad FloatArray úložištěm s maticovými operacemi,
pohledy a volitelným dispatchem do CUDA workeru. Bez GPU padá
automaticky zpět na CPU.

## Vytvoření

```lsl
tensor.from_values(values, shape)   # z Listu/FloatArray/RealArray
tensor.zeros(shape)                 # nulový tenzor
```

`shape` je List rozměrů; počet prvků musí odpovídat délce dat.

## Třída Tensor

```lsl
t.rank()   t.size()
t.get(indices)            t.set(indices, value)
t.reshape(shape)          t.view(shape, strides, offset)
t.flat_position(index)    t.contiguous_data()
t.to_device(session)      # přesun na GPU (DeviceTensor)
t.sum()                   t.dot(other_data)
t.axpy(alpha, x_data)     t.matmul(other_data, other_shape)
```

Pohledy (`view`) sdílejí úložiště — žádné kopírování. Operace, které
splňují práh akcelerace, se posílají do CUDA workeru; jinak běží na CPU.

## Raw kernely

```lsl
tensor.sum_data(data)   tensor.dot_data(left, right)
tensor.axpy_data(alpha, x, y)   tensor.matmul_data(left, right, m, k, n)
```

Pro kód citlivý na výkon bez režie metod a se statickými FloatArray typy.

## Příklad

```lsl
load tensor

t = tensor.from_values([1, 2, 3, 4], [2, 2])
print t.get([1, 1])            # 4.0
print tensor.zeros([2, 3]).size()   # 6
```

## Chyby

- `TensorShapeError` — nesoulad tvarů a dat.

## Související stránky

- `lsl man cuda` — GPU backend a DeviceTensor
- `lsl man math` — skalární numerika
