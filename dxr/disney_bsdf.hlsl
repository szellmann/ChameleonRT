#ifndef DISNEY_BSDF_HLSL
#define DISNEY_BSDF_HLSL

#include "util.hlsl"
#include "pcg_rng.hlsl"

/* Disney BSDF functions, for additional details and examples see:
 * - https://blog.selfshadow.com/publications/s2012-shading-course/burley/s2012_pbs_disney_brdf_notes_v3.pdf
 * - https://www.shadertoy.com/view/XdyyDd
 * - https://github.com/wdas/brdf/blob/master/src/brdfs/disney.brdf
 * - https://schuttejoe.github.io/post/disneybsdf/
 *
 * Variable naming conventions with the Burley course notes:
 * V -> w_o
 * L -> w_i
 * H -> w_h
 */

struct DisneyMaterial {
    float3 base_color;
    float metallic;

    float specular;
    float roughness;
    float specular_tint;
    float anisotropy;

    float sheen;
    float sheen_tint;
    float clearcoat;
    float clearcoat_gloss;

    float ior;
    float specular_transmission;
};


bool same_hemisphere(in const float3 w_o, in const float3 w_i, in const float3 n) {
    return dot(w_o, n) * dot(w_i, n) > 0.f;
}

// Sample the hemisphere using a cosine weighted distribution,
// returns a vector in a hemisphere oriented about (0, 0, 1)
float3 cos_sample_hemisphere(float2 u) {
    float2 s = 2.f * u - 1.f;
    float2 d;
    float radius = 0;
    float theta = 0;
    if (s.x == 0.f && s.y == 0.f) {
        d = s;
    } else {
        if (abs(s.x) > abs(s.y)) {
            radius = s.x;
            theta  = M_PI / 4.f * (s.y / s.x);
        } else {
            radius = s.y;
            theta  = M_PI / 2.f - M_PI / 4.f * (s.x / s.y);
        }
    }
    d = radius * float2(cos(theta), sin(theta));
    return float3(d.x, d.y, sqrt(max(0.f, 1.f - d.x * d.x - d.y * d.y)));
}

float3 spherical_dir(float sin_theta, float cos_theta, float phi) {
    return float3(sin_theta * cos(phi), sin_theta * sin(phi), cos_theta);
}

float power_heuristic(float n_f, float pdf_f, float n_g, float pdf_g) {
    float f = n_f * pdf_f;
    float g = n_g * pdf_g;
    return (f * f) / (f * f + g * g);
}

float schlick_weight(float cos_theta) {
    return pow(saturate(1.f - cos_theta), 5.f);
}

// Complete Fresnel Dielectric computation, for transmission at ior near 1
// they mention having issues with the Schlick approximation.
// eta_i: material on incident side's ior
// eta_t: material on transmitted side's ior
float fresnel_dielectric(float cos_theta_i, float eta_i, float eta_t) {
    cos_theta_i = clamp(cos_theta_i, -1.f, 1.f);
    // Potentially swap indices of refraction
    // TODO: should remove this and make sure instead that we're consistent
    if (cos_theta_i < 0.f) {
        const float x = eta_i;
        eta_i = eta_t;
        eta_t = x;
        cos_theta_i = abs(cos_theta_i);
    }

    const float sin_theta_i = sqrt(max(0.f, 1.f - pow2(cos_theta_i)));
    const float sin_theta_t = eta_i / eta_t * sin_theta_i;

    if (sin_theta_t >= 1.f) {
        return 1.f;
    }

    const float cos_theta_t = sqrt(max(0.f, 1.f - pow2(sin_theta_t)));
    const float r_parl = (eta_t * cos_theta_i - eta_i * cos_theta_t) /
        (eta_t * cos_theta_i + eta_i * cos_theta_t);
    const float r_perp = (eta_i * cos_theta_i - eta_t * cos_theta_t) /
        (eta_i * cos_theta_i + eta_t * cos_theta_t);
    return (pow2(r_parl) + pow2(r_perp)) / 2.f;
}

// TODO: Also add Fresnel conductor

float gtr_2(const float cos_theta_h, const float alpha) {
    const float alpha_sqr = pow2(alpha);
    return M_1_PI * alpha_sqr / (1.f + (alpha_sqr - 1.f) * pow2(cos_theta_h));
}

float smith_shadowing_ggx_2(const float n_dot_v, const float alpha) { 
    const float alpha_sqr = pow2(alpha);
    const float n_dot_v_sqr = pow2(n_dot_v);
    return 2.f / (1.f + sqrt(1.f + alpha_sqr * ((1.f - n_dot_v_sqr) / n_dot_v_sqr)));
}

float3 sample_lambertian_dir(in const float3 n, in const float3 v_x, in const float3 v_y, in const float2 s) {
    const float3 hemi_dir = normalize(cos_sample_hemisphere(s));
    return hemi_dir.x * v_x + hemi_dir.y * v_y + hemi_dir.z * n;
}

float3 sample_gtr_2_h(in const float3 n, in const float3 v_x, in const float3 v_y, float alpha, in const float2 s) {
    const float phi_h = 2.f * M_PI * s.x;
    const float tan_sqr_theta_h = pow2(alpha) * s.y / (1.f - s.y);
    const float cos_theta_h = 1.f / sqrt(1.f + tan_sqr_theta_h);
    const float sin_theta_h = 1.f - pow2(cos_theta_h);
    const float3 dir = normalize(spherical_dir(sin_theta_h, cos_theta_h, phi_h));
    return dir.x * v_x + dir.y * v_y + dir.z * n;
}

float lambertian_pdf(in const float3 w_i, in const float3 n) {
    float d = dot(w_i, n);
    if (d > 0.f) {
        return d * M_1_PI;
    }
    return 0.f;
}

float gtr_2_reflection_pdf(in const float3 w_o, in const float3 w_i, in const float3 n, float alpha) {
    const float3 w_h = normalize(w_i + w_o);
    const float cos_theta_h = dot(w_h, n);
    const float d = gtr_2(cos_theta_h, alpha);
    return d * cos_theta_h / (4.f * dot(w_o, w_h));
}

float3 disney_diffuse(in const DisneyMaterial mat, in const float3 n,
        in const float3 w_o, in const float3 w_i)
{
    float3 w_h = normalize(w_i + w_o);
    float n_dot_o = abs(dot(w_o, n));
    float n_dot_i = abs(dot(w_i, n));
    float i_dot_h = dot(w_i, w_h);
    float fd90 = 0.5f + 2.f * mat.roughness * i_dot_h * i_dot_h;
    float fi = schlick_weight(n_dot_i);
    float fo = schlick_weight(n_dot_o);
    return mat.base_color * M_1_PI * lerp(1.f, fd90, fi) * lerp(1.f, fd90, fo);
}

// Dielectric microfacet reflection model
float3 torrance_sparrow_reflection(in const DisneyMaterial mat, in const float3 n,
        in const float3 w_o, in const float3 w_i)
{
    float3 w_h = w_i + w_o;
    const float cos_theta_o = abs(dot(w_o, n));
    const float cos_theta_i = abs(dot(w_i, n));
    if (cos_theta_o == 0.f || cos_theta_i == 0.f || all(w_h == 0.f)) {
        return 0.f;
    }
    w_h = normalize(w_h);

    const float alpha = max(0.001f, pow2(mat.roughness));
    const float d = gtr_2(abs(dot(w_h, n)), alpha);
    const float g = smith_shadowing_ggx_2(cos_theta_o, alpha) * smith_shadowing_ggx_2(cos_theta_i, alpha);
    const float f = fresnel_dielectric(abs(dot(w_i, w_h)), mat.ior, 1.f);
    return mat.base_color * d * g * f / (4.f * cos_theta_o * cos_theta_i);
}

float3 disney_brdf(in const DisneyMaterial mat, in const float3 n,
        in const float3 w_o, in const float3 w_i, in const float3 v_x, in const float3 v_y)
{
    if (!same_hemisphere(w_o, w_i, n)) {
        return 0.f;
    }
    //return torrance_sparrow_reflection(mat, n, w_o, w_i);
    return (torrance_sparrow_reflection(mat, n, w_o, w_i) + disney_diffuse(mat, n, w_o, w_i)) / 2.f;
}

float disney_pdf(in const DisneyMaterial mat, in const float3 n,
        in const float3 w_o, in const float3 w_i, in const float3 v_x, in const float3 v_y)
{
    const float alpha = max(0.001, mat.roughness * mat.roughness);
    //return gtr_2_reflection_pdf(w_o, w_i, n, alpha);
    return (gtr_2_reflection_pdf(w_o, w_i, n, alpha) + lambertian_pdf(w_i, n)) / 2.f;
}

/* Sample a component of the Disney BRDF, returns the sampled BRDF color,
 * ray reflection direction (w_i) and sample PDF.
 */
float3 sample_disney_brdf(in const DisneyMaterial mat, in const float3 n,
        in const float3 w_o, in const float3 v_x, in const float3 v_y, inout PCGRand rng,
        out float3 w_i, out float pdf)
{
    int component = 0;
    if (mat.specular_transmission == 0.f) {
        component = pcg32_randomf(rng) * 2.f;
        component = clamp(component, 0, 1);
    } else {
        component = pcg32_randomf(rng) * 4.f;
        component = clamp(component, 0, 3);
        // TODO: This seems to help a bit? If we're coming from the back
        // we have to be transmitting through
        // This will bias it though
        if (dot(w_o, n) < 0.f) {
            component = 3;
        }
    }

    const float2 samples = float2(pcg32_randomf(rng), pcg32_randomf(rng));
    if (component == 0) {
		w_i = sample_lambertian_dir(n, v_x, v_y, samples);
    } else {
        const float alpha = max(0.001, mat.roughness * mat.roughness);
        const float3 w_h = sample_gtr_2_h(n, v_x, v_y, alpha, samples);
        w_i = reflect(-w_o, w_h);
        if (!same_hemisphere(w_o, w_i, n)) {
            w_i = -w_i;
        }
    }
    pdf = disney_pdf(mat, n, w_o, w_i, v_x, v_y);
    return disney_brdf(mat, n, w_o, w_i, v_x, v_y);
}

#endif

