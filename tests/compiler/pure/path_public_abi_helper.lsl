function checked_length(value):
    return len(value)
end

function result():
    try:
        call checked_length(42)
    else:
        return last_error()
    end
    return "unexpected success"
end
