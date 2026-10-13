import hw1_common;

bool circle_fill(float2 p, Circle c) {
    return distance(p, c.center) <= c.radius;
}

bool circle_stroke(float2 p, Circle c, float stroke_width) {
    return abs(distance(p, c.center) - c.radius) <= stroke_width / 2.0;
}

void polyline_test(float2 p, Polyline pl, StructuredBuffer<float2> points,
                   float stroke_width, out bool in_fill, out bool in_stroke) {
    in_stroke = false;
    int winding = 0;

    int num_pts = pl.pts_end - pl.pts_begin;

    int num_segments;
    if (pl.closed) {
        num_segments = num_pts;
    } else {
        num_segments = num_pts - 1;
    }

    for (int i = 0; i < num_segments; i++) {
        int next = i + 1;
        if (next == num_pts) {
            next = 0;
        }
        float2 A = points[pl.pts_begin + i];
        float2 B = points[pl.pts_begin + next];

        float t = dot(p - A, B - A) / dot(B - A, B - A);
        if (t >= 0.0 && t <= 1.0) {
            float2 closest = A + t * (B - A);
            if (distance(p, closest) <= stroke_width / 2.0) {
                in_stroke = true;
            }
        }

        bool b_is_join = pl.closed || (i < num_segments - 1);
        if (b_is_join && distance(p, B) <= stroke_width / 2.0) {
            in_stroke = true;
        }

        if ((A.y <= p.y) != (B.y <= p.y)) {
            float s = (p.y - A.y) / (B.y - A.y);
            float x_cross = A.x + s * (B.x - A.x);
            if (x_cross > p.x) {
                if (B.y > A.y) {
                    winding += 1;
                } else {
                    winding -= 1;
                }
            }
        }
    }

    in_fill = pl.closed && winding != 0;
}

void bezier_test(float2 p, QuadraticBezier bz, StructuredBuffer<float2> points,
                 float stroke_width, out bool in_fill, out bool in_stroke) {
    in_stroke = false;
    int winding = 0;

    int num_pts = bz.pts_end - bz.pts_begin;

    int num_curves;
    if (bz.closed) {
        num_curves = num_pts / 2;
    } else {
        num_curves = (num_pts - 1) / 2;
    }

    for (int k = 0; k < num_curves; k++) {
        int i0 = 2 * k;
        int i1 = 2 * k + 1;
        int i2 = 2 * k + 2;
        if (i2 == num_pts) {
            i2 = 0;       
        }
        float2 p0 = points[bz.pts_begin + i0];
        float2 p1 = points[bz.pts_begin + i1];
        float2 p2 = points[bz.pts_begin + i2];

        // q(t) = A t^2 + B t + C
        float2 A = p0 - 2.0 * p1 + p2;
        float2 B = 2.0 * (p1 - p0);
        float2 C = p0;

        float2 qroots;
        if (solve_quadratic(A.y, B.y, C.y - p.y, qroots)) {
            float ts[2] = { qroots.x, qroots.y };
            for (int r = 0; r < 2; r++) {
                float t = ts[r];
                if (t >= 0.0 && t < 1.0) {                  
                    float x_cross = A.x * t * t + B.x * t + C.x;
                    float dy = 2.0 * A.y * t + B.y;
                    if (x_cross > p.x) {
                        if (dy > 0.0) {
                            winding += 1;
                        } else if (dy < 0.0) {
                            winding -= 1;
                        }
                    }
                }
            }
        }

        float2 D = C - p;
        float3 croots;
        int n = solve_cubic(2.0 * dot(A, A),
                            3.0 * dot(A, B),
                            dot(B, B) + 2.0 * dot(A, D),
                            dot(B, D),
                            croots);
        float cts[3] = { croots.x, croots.y, croots.z };
        for (int r = 0; r < n; r++) {
            float t = cts[r];
            if (t >= 0.0 && t <= 1.0) {
                float2 q = A * t * t + B * t + C;
                if (distance(p, q) <= stroke_width / 2.0) {
                    in_stroke = true;
                }
            }
        }

        // ---- Round join at p2 ----
        bool p2_is_join = bz.closed || (k < num_curves - 1);
        if (p2_is_join && distance(p, p2) <= stroke_width / 2.0) {
            in_stroke = true;
        }
    }

    in_fill = bz.closed && winding != 0;
}

float3 shade(float2 p, float3 background, int num_shapes,
             StructuredBuffer<Shape> shapes,
             StructuredBuffer<Circle> circles,
             StructuredBuffer<Polyline> polylines,
             StructuredBuffer<QuadraticBezier> quadratic_beziers,
             StructuredBuffer<float2> points) {
    float3 col = background;

    for (int i = num_shapes - 1; i >= 0; i--) {
        Shape s = shapes[i];
        float2 q = mul(s.world_to_obj, float3(p, 1.0)).xy;
        bool in_fill = false;
        bool in_stroke = false;

        if (s.type == ShapeType.Circle) {
            Circle c = circles[s.index];
            in_fill = circle_fill(q, c);
            in_stroke = circle_stroke(q, c, s.stroke_width);
        } else if (s.type == ShapeType.Polyline) {
            polyline_test(q, polylines[s.index], points, s.stroke_width, in_fill, in_stroke);
        } else if (s.type == ShapeType.QuadraticBezier) {
            bezier_test(q, quadratic_beziers[s.index], points, s.stroke_width, in_fill, in_stroke);
        }

        if (s.use_fill && in_fill) {
            float3 fc = s.fill_rgba.rgb;
            float fa = s.fill_rgba.a;
            col = fa * fc + (1.0 - fa) * col;
        }
        if (s.use_stroke && in_stroke) {
            float3 sc = s.stroke_rgba.rgb;
            float sa = s.stroke_rgba.a;
            col = sa * sc + (1.0 - sa) * col;
        }
    }

    return col;
}

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int samples_per_axis,
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> quadratic_beziers,
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    int N = samples_per_axis;
    float x0 = float(tid.x);
    float y0 = float(height) - float(tid.y) - 1.0;

    float3 sum = float3(0.0);
    for (int sy = 0; sy < N; sy++) {
        for (int sx = 0; sx < N; sx++) {
            float x = x0 + (float(sx) + 0.5) / float(N);
            float y = y0 + (float(sy) + 0.5) / float(N);
            sum += shade(float2(x, y), background, num_shapes,
                         shapes, circles, polylines, quadratic_beziers, points);
        }
    }

    float3 col = sum / float(N * N);
    image[tid] = float4(col, 1.0);
}