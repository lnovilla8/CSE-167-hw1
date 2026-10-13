import hw1_common;

[shader("compute")]
[numthreads(8, 8, 1)]
void compute_main(uint2 tid : SV_DispatchThreadID,
                  StructuredBuffer<float2> polyline,
                  uniform int num_polyline,
                  uniform bool is_closed,
                  uniform bool use_fill_color,
                  uniform float3 fill_color,
                  uniform bool use_stroke_color,
                  uniform float3 stroke_color,
                  uniform float stroke_width,
                  RWTexture2D<float4> image) {
    uint width, height;
    image.GetDimensions(width, height);
    if (tid.x >= width || tid.y >= height) {
        return;
    }
    
    
    float p_x = float(tid.x) + 0.5;
    float p_y = float(height) - float(tid.y) - 0.5;
    float2 pixel_center = float2(p_x, p_y);

    float3 col = float3(0.5, 0.5, 0.5);
    bool in_stroke = false;
    int winding = 0;

    int num_segments;
    if (is_closed) {
        num_segments = num_polyline;
    } else {
        num_segments = num_polyline - 1;
    }

    for (int i = 0; i < num_segments; i++) {
        float2 A = polyline[i];

        int next = i + 1;
        if (next == num_polyline) {
            next = 0;
        }
        float2 B = polyline[next];

        float t = dot(pixel_center - A, B - A) / dot(B - A, B - A);

        if (t >= 0.0 && t <= 1.0) {
            float2 closest = A + t * (B - A); 
            if (distance(pixel_center, closest) <= stroke_width / 2.0) {
                in_stroke = true;
            }
        }

        bool b_is_join = is_closed || (i < num_segments - 1);
        if (b_is_join && distance(pixel_center, B) <= stroke_width / 2.0) {
            in_stroke = true;
        }

        if ((A.y <= pixel_center.y) != (B.y <= pixel_center.y)) {
            float s = (pixel_center.y - A.y) / (B.y - A.y);
            float x_cross = A.x + s * (B.x - A.x);
  
            if (x_cross > pixel_center.x) {
                if (B.y > A.y) {
                    winding += 1;   
                } else {
                    winding -= 1;  
                }
            }
        }
    }

    if (use_fill_color && is_closed && winding != 0) {
        col = fill_color;
    }

    if (use_stroke_color && in_stroke) {
        col = stroke_color;
    }

    image[tid] = float4(col, 1.0);
}
