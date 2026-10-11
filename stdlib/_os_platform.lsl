# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _os_linux_x86_64 as implementation


function checked_argument(value, label):
    return implementation.checked_argument(value, label)
end

function which(name):
    return implementation.which(name)
end

function which_trusted(name):
    return implementation.which_trusted(name)
end
