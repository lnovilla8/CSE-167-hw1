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

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  uniform float3 background,
                  uniform int /*samples_per_axis*/, // ignore for now
                  StructuredBuffer<Shape> shapes,
                  uniform int num_shapes,
                  StructuredBuffer<Circle> circles,
                  StructuredBuffer<Polyline> polylines,
                  StructuredBuffer<QuadraticBezier> /*quadratic_beziers*/, // ignore for now
                  StructuredBuffer<float2> points,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }

    float p_x = float(tid.x) + 0.5;
    float p_y = float(height) - float(tid.y) - 0.5;
    float2 p = float2(p_x, p_y);

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
        }

        // Fill first, then this shape's stroke on top
        if (s.use_fill && in_fill) {
            col = s.fill_rgba.rgb;
        }
        if (s.use_stroke && in_stroke) {
            col = s.stroke_rgba.rgb;
        }
    }

    image[tid] = float4(col, 1.0);
}
