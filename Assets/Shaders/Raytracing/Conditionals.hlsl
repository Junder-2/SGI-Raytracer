float WhenEquals(float x, float y) {
    return 1.0 - abs(sign(x - y));
}

float WhenNEquals(float x, float y) {
    return abs(sign(x - y));
}

float WhenGreater(float x, float y) {
    return max(sign(x - y), 0.0);
}

float WhenLess(float x, float y) {
    return max(sign(y - x), 0.0);
}

float WhenGreaterEquals(float x, float y) {
    return 1.0 - WhenLess(x, y);
}

float WhenLessEquals(float x, float y) {
    return 1.0 - WhenGreater(x, y);
}

float And(float a, float b) {
    return a * b;
}

float Or(float a, float b) {
    return min(a + b, 1.0);
}

float Xor(float a, float b) {
    return (a + b) % 2.0;
}

float Not(float a) {
    return 1.0 - a;
}