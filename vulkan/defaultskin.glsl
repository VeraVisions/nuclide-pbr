//======= Copyright (c) 2015-2021 Vera Visions LLC. All rights reserved. =======
//
// Purpose: 
//
// Lightmapped surface that contains an environment cube as a reflection.
// Alpha channel of the diffuse decides reflectivity.
//==============================================================================
!!permu FULLBRIGHT
!!permu UPPERLOWER
!!permu FOG
!!permu BUMP
!!permu REFLECTCUBEMASK
!!cvarf r_glsl_offsetmapping=0
!!cvarf r_glsl_offsetmapping_scale=0.04
!!cvarf gl_specular=0
!!cvarb r_fog_exp2=true
!!samps diffuse normalmap upper lower specular fullbright reflectcube reflectmask

#include "sys/defs.h"

layout(location=0) varying vec2 tc;
layout(location=1) varying vec3 lightvector;
layout(location=2) varying vec3 light;

#if defined(SPECULAR)
layout(location=3) varying vec3 eyevector;
layout(location=4) varying mat3 invsurface;
#endif

// our basic vertex shader
#ifdef VERTEX_SHADER
	#include "sys/skeletal.h"

	float lambert( vec3 normal, vec3 dir ) {
		return dot( normal, dir );
	}
	float halflambert( vec3 normal, vec3 dir ) {
		return ( dot( normal, dir ) * 0.5 ) + 0.5;
	}

	void main ()
	{
		vec3 n, s, t, w;
		gl_Position = skeletaltransform_wnst(w,n,s,t);

		if (SPECULAR) {
			vec3 eyeminusvertex = e_eyepos - w.xyz;
			eyevector.x = dot(eyeminusvertex, s.xyz);
			eyevector.y = dot(eyeminusvertex, t.xyz);
			eyevector.z = dot(eyeminusvertex, n.xyz);
			invsurface[0] = s;
			invsurface[1] = t;
			invsurface[2] = n;
		}

		light = e_light_ambient + (e_light_mul * lambert(n, e_light_dir));

		tc = v_texcoord;
		lightvector.x = dot(e_light_dir, s.xyz);
		lightvector.y = dot(e_light_dir, t.xyz);
		lightvector.z = dot(e_light_dir, n.xyz);
	}
#endif

#ifdef FRAGMENT_SHADER
	#include "sys/fog.h"
	#include "sys/offsetmapping.h"

	float LightingFuncGGX(vec3 N, vec3 V, vec3 L, float roughness, float F0)
	{
		float alpha = roughness*roughness;

		vec3 H = normalize(V+L);

		float dotNL = clamp(dot(N,L), 0.0, 1.0);
		float dotLH = clamp(dot(L,H), 0.0, 1.0);
		float dotNH = clamp(dot(N,H), 0.0, 1.0);

		float F, D, vis;

		// D
		float alphaSqr = alpha*alpha;
		float pi = 3.14159f;
		float denom = dotNH * dotNH *(alphaSqr-1.0) + 1.0f;
		D = alphaSqr/(pi * denom * denom);

		// F
		float dotLH5 = pow(1.0f-dotLH,5);
		F = F0 + (1.0-F0)*(dotLH5);

		// V
		float k = alpha/2.0f;
		float k2 = k*k;
		float invK2 = 1.0f-k2;
		vis = 1.0/(dotLH*dotLH*invK2 + k2);

		float specular = dotNL * D * F * vis;
		return specular;
	}

	void main ()
	{
		vec2 tex_c;
		vec3 normal_f;
		float ao;
		vec4 out_f;

		if (OFFSETMAPPING) {
			vec2 tcoffsetmap = offsetmap(s_normalmap, tc, eyevector);
			tex_c = tcoffsetmap;
		} else {
			tex_c = tc;
		}

		vec4 albedo_f = texture2D(s_diffuse, tex_c);

		if (BUMP) {
			normal_f = normalize(texture2D(s_normalmap, tex_c).rgb - 0.5);
		} else {
			normal_f = vec3(0.0, 0.0, 1.0);
		}

		if (UPPERLOWER) {
			vec4 uc = texture2D(s_upper, tex_c);
			albedo_f.rgb += uc.rgb * e_uppercolour * uc.a;
			vec4 lc = texture2D(s_lower, tex_c);
			albedo_f.rgb += lc.rgb * e_lowercolour * lc.a;
		}

		if (SPECULAR) {
			float metalness_f = texture2D(s_specular, tex_c).r;
			float roughness_f = texture2D(s_specular, tex_c).g;
			ao = texture2D(s_specular, tex_c).b;

			/* coords */
			vec3 cube_c;

			/* calculate cubemap texcoords */
			cube_c = reflect(-normalize(eyevector), normal_f.rgb);
			cube_c = cube_c.x * invsurface[0] + cube_c.y * invsurface[1] + cube_c.z * invsurface[2];
			cube_c = (m_model * vec4(cube_c.xyz, 0.0)).xyz;

			/* do PBR reflection using cubemap */
			out_f = albedo_f + (metalness_f * textureCube(s_reflectcube, cube_c));

			/* do PBR specular using our handy function */
			out_f += (LightingFuncGGX(normal_f, normalize(eyevector), normalize(lightvector), roughness_f, 0.25) * gl_FragColor);
		} else {
			out_f = albedo_f;
		}

		/* this isn't necessary if we're not doing lightgrid terms */
		out_f.rgb *= light;

		if (SPECULAR) {
			out_f.rgb *= ao;
		}

		if (FULLBRIGHT) {
			vec4 fb = texture2D(s_fullbright, tex_c);
			out_f.rgb += fb.rgb * fb.a * e_glowmod.rgb;
		}

		gl_FragColor = fog4(out_f * e_colourident);
	}
#endif
