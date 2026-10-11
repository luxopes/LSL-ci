# Veřejné API; operace hostitele poskytuje modul vybraný cílem.

load _ai_linux_x86_64 as implementation


function thread_id():
    return implementation.thread_id()
end
