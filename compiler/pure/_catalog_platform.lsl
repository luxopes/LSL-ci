# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load catalog_linux_x86_64 as implementation


function fail(message):
    return implementation.fail(message)
end

function library_file(path):
    return implementation.library_file(path)
end

function directory_names(directory):
    return implementation.directory_names(directory)
end
