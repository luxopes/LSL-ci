# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _random_linux_x86_64 as implementation


function _entropy(n):
    return implementation._entropy(n)
end
