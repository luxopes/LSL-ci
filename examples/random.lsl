load random

rng = random.Random(42)
print [rng.randint(1, 6) for i in rang(8)]
print rng.choices(["A", "B", "C"], weights=[1, 2, 3], k=6)
deck = [i for i in rang(10)]
call rng.shuffle(deck)
print deck
print rng.sample(deck, 3)
print {i:rng.normalvariate(mu=0, sigma=1) for i in rang(3)}
saved = rng.getstate()
first = rng.random()
call rng.setstate(saved)
print first == rng.random()
