
// Optional marker channel tolerance (OFF by default = unchanged behaviour).
// Set to 1 to match marker signature channels with |diff|<=1 per channel.
// Enable on 26.3 if marker channels stop working due to OIT rounding (±1).
#define SS_MARKER_TOLERANCE 0

// define distinct values, counting from 1:
#define EXAMPLE_GREYSCALE_CHANNEL 1
#define EXAMPLE_ROTATION_CHANNEL 2

/*
signature:
 ADD_MARKER(channel, green, alpha, op, rate)
*/
// append different marker definitions
#define LIST_MARKERS ADD_MARKER(EXAMPLE_GREYSCALE_CHANNEL, 253, 251, 1, 0.1) ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 251, 251, 0, 0.0) ADD_MARKER(EXAMPLE_ROTATION_CHANNEL, 252, 251, 4, 0.4)

#define MARKER_RED 254

// Screen pixel that the marker ends up on if it uses channel k:
// Mapping follows structure that is like an inverted cantor pairing (but only producing coordinates with an even sum)
#define MARKER_POS(k) (ivec2(2*int(ceil(sqrt(float(k))) - 1.0),0) + (k - int((ceil(sqrt(float(k))) - 1.0)*(ceil(sqrt(float(k))) - 1.0)) - 1)*ivec2(-1, 1))
