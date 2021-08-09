//======= Copyright (c) 2015-2021 Vera Visions LLC. All rights reserved. =======
//
// Purpose: 
//
// Lightmapped surface that contains an environment cube as a reflection.
// Alpha channel of the diffuse decides reflectivity.
//==============================================================================
!!permu FOG
!!permu FULLBRIGHT
!!permu BUMP
!!permu REFLECTCUBEMASK
!!samps diffuse normalmap specular fullbright lightmap
!!samps deluxemap reflectmask reflectcube
!!argb vertexlit=0
!!argf mask=1.0
!!argb masklt=false
// we have to define these
!!cvarf r_glsl_offsetmapping=0.0
!!cvarf r_glsl_offsetmapping_scale=0.04
!!cvarf gl_specular=1.0
!!cvarb r_fog_exp2=true

#include "sys/defs.h"

layout(location=0) varying vec2 tc;
layout(location=1) varying vec2 lm0;

#ifdef SPECULAR
layout(location=3) varying vec3 eyevector;
layout(location=4) varying mat3 invsurface;
#endif

#ifdef LIGHTSTYLED
varying vec2 lm1, lm2, lm3;
#endif

#ifdef VERTEX_SHADER
	void lightmapped_init(void)
	{
		lm0 = v_lmcoord;
		#ifdef LIGHTSTYLED
		lm1 = v_lmcoord2;
		lm2 = v_lmcoord3;
		lm3 = v_lmcoord4;
		#endif
	}

	void main (void)
	{
		lightmapped_init();

		if (SPECULAR)
		{
			invsurface[0] = v_svector;
			invsurface[1] = v_tvector;
			invsurface[2] = v_normal;
			vec3 eyeminusvertex = e_eyepos - v_position.xyz;
			eyevector.x = dot(eyeminusvertex, v_svector.xyz);
			eyevector.y = dot(eyeminusvertex, v_tvector.xyz);
			eyevector.z = dot(eyeminusvertex, v_normal.xyz);
		}

		tc = v_texcoord;
		gl_Position = ftetransform();
	}
#endif

#ifdef FRAGMENT_SHADER
	#include "sys/fog.h"
	#include "sys/offsetmapping.h"

	#ifdef LIGHTSTYLED
		#define LIGHTMAP0 texture2D(s_lightmap0, lm0).rgb
		#define LIGHTMAP1 texture2D(s_lightmap1, lm1).rgb
		#define LIGHTMAP2 texture2D(s_lightmap2, lm2).rgb
		#define LIGHTMAP3 texture2D(s_lightmap3, lm3).rgb
	#else
		#define LIGHTMAP texture2D(s_lightmap, lm0).rgb 
	#endif

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

	vec3 lightmap_fragment()
	{
		vec3 lightmaps;

	#ifdef LIGHTSTYLED
		lightmaps  = LIGHTMAP0 * e_lmscale[0].rgb;
		lightmaps += LIGHTMAP1 * e_lmscale[1].rgb;
		lightmaps += LIGHTMAP2 * e_lmscale[2].rgb;
		lightmaps += LIGHTMAP3 * e_lmscale[3].rgb;
	#else
		lightmaps  = LIGHTMAP * e_lmscale.rgb;
	#endif
		return lightmaps;
	}

#if r_skipNormal==0
	vec3 lightmap_fragment(vec3 normal_f)
	{
	#ifndef DELUXE
		return lightmap_fragment();
	#else
		vec3 lightmaps;

	#ifdef LIGHTSTYLED
		lightmaps  = LIGHTMAP0 * e_lmscale[0].rgb * dot(normal_f, (texture2D(s_deluxemap0, lm0).rgb - 0.5) * 2.0);
		lightmaps += LIGHTMAP1 * e_lmscale[1].rgb * dot(normal_f, (texture2D(s_deluxemap1, lm1).rgb - 0.5) * 2.0);
		lightmaps += LIGHTMAP2 * e_lmscale[2].rgb * dot(normal_f, (texture2D(s_deluxemap2, lm2).rgb - 0.5) * 2.0);
		lightmaps += LIGHTMAP3 * e_lmscale[3].rgb * dot(normal_f, (texture2D(s_deluxemap3, lm3).rgb - 0.5) * 2.0);
	#else 
		lightmaps  = LIGHTMAP * e_lmscale.rgb * dot(normal_f, (texture2D(s_deluxemap, lm0).rgb - 0.5) * 2.0);
	#endif

		return lightmaps;
	#endif
	}
#endif

	void main (void)
	{
		vec2 tex_c;
		float ao;

		if (OFFSETMAPPING) {
			tex_c = offsetmap(s_normalmap, tex_c, eyevector);
		} else {
			tex_c = tc;
		}

		/* samplers */
		vec4 albedo_f = texture2D(s_diffuse, tex_c); // diffuse RGBA
		vec3 normal_f = normalize(texture2D(s_normalmap, tex_c).rgb - 0.5); // normalmap RGB

		/* deluxe/light */
		vec3 deluxe = normalize((texture2D(s_deluxemap, lm0).rgb - 0.5));

		if (SPECULAR) {
			float metalness_f =texture2D(s_specular, tex_c).r; // specularmap R
			float roughness_f = texture2D(s_specular, tex_c).g; // specularmap G
			ao = texture2D(s_specular, tex_c).b; // specularmap B
			
			/* coords */
			vec3 cube_c;

			/* calculate cubemap texcoords */
			cube_c = reflect(-normalize(eyevector), normal_f.rgb);
			cube_c = cube_c.x * invsurface[0] + cube_c.y * invsurface[1] + cube_c.z * invsurface[2];
			cube_c = (m_model * vec4(cube_c.xyz, 0.0)).xyz;

			/* do PBR reflection using cubemap */
			gl_FragColor = albedo_f + (metalness_f * textureCube(s_reflectcube, cube_c));

			/* do PBR specular using our handy function */
			gl_FragColor += (LightingFuncGGX(normal_f, normalize(eyevector), deluxe, roughness_f, 0.25f) * gl_FragColor);
		} else {
			gl_FragColor = albedo_f;
		}

		/* calculate lightmap fragment on top */
		gl_FragColor.rgb *= lightmap_fragment(normal_f);

		/* emissive texture/fullbright bits */
		if (FULLBRIGHT) {
			vec3 emission_f = texture2D(s_fullbright, tex_c).rgb; // fullbrightmap RGB
			gl_FragColor.rgb += emission_f;
		}

		/* ambient occlusion */
		if (SPECULAR) {
			gl_FragColor.rgb *= ao;
		}

		/* and let the engine add fog on top */
		gl_FragColor = fog4(gl_FragColor);
	}
#endif
