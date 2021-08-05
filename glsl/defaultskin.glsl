//======= Copyright (c) 2015-2021 Vera Visions LLC. All rights reserved. =======
//
// Purpose: 
//
// Lightmapped surface that contains an environment cube as a reflection.
// Alpha channel of the diffuse decides reflectivity.
//==============================================================================

!!ver 100 150

!!permu FOG
!!permu BUMP
!!permu DELUXE
!!permu SPECULAR
!!permu FULLBRIGHT
!!permu FAKESHADOWS
!!permu OFFSETMAPPING
!!permu SKELETAL

!!samps diffuse normalmap specular fullbright upper lower paletted reflectmask reflectcube

!!cvarf r_glsl_offsetmapping_scale
!!cvarf gl_specular

#include "sys/defs.h"

varying vec2 tc;
varying vec3 lightvector;
varying vec3 light;

#ifdef SPECULAR
varying vec3 eyevector;
varying mat3 invsurface;
#endif

#ifdef VERTEX_SHADER
	#include "sys/skeletal.h"

	void main ()
	{
		vec3 n, s, t, w;
		gl_Position = skeletaltransform_wnst(w,n,s,t);

	#ifdef SPECULAR
		vec3 eyeminusvertex = e_eyepos - w.xyz;
		eyevector.x = dot(eyeminusvertex, s.xyz);
		eyevector.y = dot(eyeminusvertex, t.xyz);
		eyevector.z = dot(eyeminusvertex, n.xyz);
		invsurface[0] = s;
		invsurface[1] = t;
		invsurface[2] = n;
	#endif

		tc = v_texcoord;
		lightvector.x = dot(e_light_dir, s.xyz);
		lightvector.y = dot(e_light_dir, t.xyz);
		lightvector.z = dot(e_light_dir, n.xyz);
	}
#endif


#ifdef FRAGMENT_SHADER
	#include "sys/fog.h"

	#if defined(SPECULAR)
	uniform float cvar_gl_specular;
	#endif

	#ifdef OFFSETMAPPING
	#include "sys/offsetmapping.h"
	#endif

	vec3 LightingFuncShlick(vec3 N, vec3 V, vec3 L, float roughness, vec3 Cdiff, vec3 F0)
	{
		vec3 H = normalize(V+L);
		float NL = clamp(dot(N,L), 0.001, 1.0);
		float LH = clamp(dot(L,H), 0.0, 1.0);
		float NH = clamp(dot(N,H), 0.0, 1.0);
		float NV = clamp(abs(dot(N,V)), 0.001, 1.0);
		float VH = clamp(dot(V,H), 0.0, 1.0);
		float PI = 3.14159f;

		//Fresnel Schlick
		vec3 F = F0 + (1.0-F0)*pow(1.0-VH, 5.0);

		//Schlick
		float k = roughness*0.79788456080286535587989211986876;
		float G = (LH/(LH*(1.0-k)+k)) * (NH/(NH*(1.0-k)+k));

		float a = roughness*roughness;
		a *= a;
		float t = (NH*NH*(a-1.0)+1.0);
		float D = a/(PI*t*t);

		return ((1.0-F)*(Cdiff/PI) + 
			(F*G*D)/(4*NL*NV)*NL);
	}

	void main ()
	{
		#ifdef OFFSETMAPPING
			vec2 tcoffsetmap = offsetmap(s_normalmap, tc, eyevector);
			#define tc tcoffsetmap
		#endif

		vec4 albedo_f = texture2D(s_diffuse, tc); // diffuse RGBA
		vec3 normal_f = normalize(texture2D(s_normalmap, tc).rgb - 0.5); // normalmap RGB

		#ifdef SPECULAR
			float metalness_f =texture2D(s_specular, tc).r; // specularmap R
			float roughness_f = texture2D(s_specular, tc).g; // specularmap G
			float ao = texture2D(s_specular, tc).b; // specularmap B
		#endif

		#ifdef UPPER
			vec4 uc = texture2D(s_upper, tc);
			albedo_f.rgb += uc.rgb*e_uppercolour*uc.a;
		#endif

		#ifdef LOWER
			vec4 lc = texture2D(s_lower, tc);
			albedo_f.rgb += lc.rgb*e_lowercolour*lc.a;
		#endif

		#ifdef SPECULAR
			vec3 bumps = normalize(vec3(texture2D(s_normalmap, tc)) - 0.5);
			const vec3 dielectricSpecular = vec3(0.04, 0.04, 0.04);	//non-metals have little specular (but they do have some)
			const vec3 black = vec3(0, 0, 0); //pure metals are asumed to be pure specular

			vec3 F0 = mix(dielectricSpecular, albedo_f.rgb, metalness_f);
			albedo_f.rgb = mix(albedo_f.rgb * (1.0 - dielectricSpecular.r), black, metalness_f);

			vec3 nl = normalize(lightvector);
			albedo_f.rgb += LightingFuncShlick(bumps, normalize(eyevector), nl, roughness_f, albedo_f.rgb, F0);
			//albedo_f.rgb = eyevector;//vec3(dot(nl, bumps));
			//albedo_f.rgb = vec3(0);
			albedo_f.rgb *= vec3(dot(nl, bumps));

		#endif

		#ifdef REFLECTCUBEMASK
			vec3 rtc = reflect(-eyevector, bumps);
			rtc = rtc.x*invsurface[0] + rtc.y*invsurface[1] + rtc.z*invsurface[2];
			rtc = (m_model * vec4(rtc.xyz,0.0)).xyz;
			albedo_f.rgb += texture2D(s_reflectmask, tc).rgb * textureCube(s_reflectcube, rtc).rgb;
		#endif

			//albedo_f.rgb *= light;
			//albedo_f.rgb *= ao;	//ambient occlusion

		#ifdef FULLBRIGHT
			vec4 fb = texture2D(s_fullbright, tc);
			#ifdef PBR_SPEC
				albedo_f.rgb *= fb.a;	//ambient occlusion
				albedo_f.rgb += fb.rgb * e_glowmod.rgb;
			#else
				//albedo_f.rgb = mix(albedo_f.rgb, fb.rgb, fb.a);
				albedo_f.rgb += fb.rgb * fb.a * e_glowmod.rgb;
			#endif
		#endif

		gl_FragColor = fog4(albedo_f * e_colourident);
	}
#endif
