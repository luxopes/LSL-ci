load tui
terminal = tui.Terminal()
for expected in ["char:a", "char:b", "up", "pagedown", "char:ž", "enter", "ctrl-c", "ctrl-d", "esc", "char:q", "none"]:
    actual = terminal.read_key()
    if actual != expected:
        Error(TestFailure: "terminal key mismatch")
    end
end
print "buffered terminal keys passed"
