#ifndef MERCENARIES_SLOPE_SLIDE_H
#define MERCENARIES_SLOPE_SLIDE_H
#include <math.h>
/* Retail direct-input movement resets horizontal velocity every update. On a
 * plane with normal.y = n, projection retains r = 1 - n*n of slide momentum.
 * Preserve that 60 Hz response over dt: retention = pow(r, 60*dt). Blend the
 * reset and gravity impulse together, preserving the authored terminal speed.
 * Only called for grounded steep-slope sliding in the direct-input path. */
static void merc_slope_slide_step(float dt, const float normal[3],
                                  const float previous[3], float desired[3],
                                  float gravity[3])
{
    const float reference_dt = 1.0f / 60.0f;
    if (!isfinite(dt) || !(dt > 0.0f) || dt == reference_dt) return;
    double length = 0.0;
    for (unsigned i = 0; i < 3; ++i) {
        if (!isfinite(normal[i]) || !isfinite(previous[i]) ||
            !isfinite(desired[i]) || !isfinite(gravity[i])) return;
        length += (double)normal[i] * normal[i];
    }
    if (length < 0.99 || length > 1.01 || normal[1] <= 0.0f || normal[1] >= 1.0f) return;
    const double loss = (double)normal[1] * normal[1];
    const double steps = (double)dt / reference_dt;
    const double blend = -expm1(log1p(-loss) * steps) / loss;
    const double gravity_scale = blend / steps;
    /* Only slope-directed momentum persists through retail contact. Across
     * the slope, retail input replaces velocity immediately. Keeping that
     * component direct also avoids overshoot when dt spans multiple ticks. */
    const double horizontal_length = (double)normal[0] * normal[0] +
                                     (double)normal[2] * normal[2];
    if (!(horizontal_length > 0.0)) return;
    const double difference = ((desired[0] - (double)previous[0]) * normal[0] +
                               (desired[2] - (double)previous[2]) * normal[2]) /
                              horizontal_length;
    desired[0] = (float)(desired[0] + (blend - 1.0) * difference * normal[0]);
    desired[2] = (float)(desired[2] + (blend - 1.0) * difference * normal[2]);
    for (unsigned i = 0; i < 3; ++i) gravity[i] = (float)(gravity[i] * gravity_scale);
}
#endif
