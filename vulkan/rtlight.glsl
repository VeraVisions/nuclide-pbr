//======= Copyright (c) 2015-2021 Vera Visions LLC. All rights reserved. =======
//
// Purpose: 
//
// Lightmapped surface that contains an environment cube as a reflection.
// Alpha channel of the diffuse decides reflectivity.
//==============================================================================
!!samps diffuse normalmap specular shadowmap upper lower reflectmask reflectcube projectionmap
!!cvarf r_glsl_offsetmapping=0
!!cvarf gl_specular=0
!!cvarf r_glsl_offsetmapping_scale=0.04
!!cvari r_glsl_pcf=5
!!permu BUMP
!!permu UPPERLOWER
!!permu REFLECTCUBEMASK
!!argb pcf=0
!!argb spot=0
!!argb cube=0
!!permu FOG
!!cvarb r_fog_exp2=true

#include "sys/defs.h"

#define USE_ARB_SHADOW

#ifndef USE_ARB_SHADOW
#define sampler2DShadow sampler2D
#else
#define shadow2D texture
#endif

#if 0 && defined(GL_ARB_texture_gather) && defined(PCF) 
#extension GL_ARB_texture_gather : enable
#endif

layout(location = 0) varying vec2 tcbase;
layout(location = 1) varying vec3 lightvector;
layout(location = 2) varying vec3 eyevector;
layout(location = 3) varying vec4 vtexprojcoord;
layout(location = 4) varying mat3 invsurface;

#ifdef VERTEX_SHADER
	#include "sys/skeletal.h"
	void main ()
	{
		vec3 n, s, t, w;
		gl_Position = skeletaltransform_wnst(w,n,s,t);
		tcbase = v_texcoord;	//pass the texture coords straight through
		vec3 lightminusvertex = l_lightposition - w.xyz;

	#ifdef NOBUMP
		//the only important thing is distance
		lightvector = lightminusvertex;
	#else
		//the light direction relative to the surface normal, for bumpmapping.
		lightvector.x = dot(lightminusvertex, s.xyz);
		lightvector.y = dot(lightminusvertex, t.xyz);
		lightvector.z = dot(lightminusvertex, n.xyz);
	#endif

	#ifdef SPECULAR
		vec3 eyeminusvertex = e_eyepos - w.xyz;
		eyevector.x = dot(eyeminusvertex, s.xyz);
		eyevector.y = dot(eyeminusvertex, t.xyz);
		eyevector.z = dot(eyeminusvertex, n.xyz);
		invsurface[0] = v_svector;
		invsurface[1] = v_tvector;
		invsurface[2] = v_normal;
	#endif

	#if defined(PCF) || defined(SPOT) || defined(CUBE)
		//for texture projections/shadowmapping on dlights
		vtexprojcoord = (l_cubematrix*vec4(w.xyz, 1.0));
	#endif
	}
#endif


#ifdef FRAGMENT_SHADER
	//uniform vec4 l_shadowmapproj; //light projection matrix info
	//uniform vec2 l_shadowmapscale;	//xy are the texture scale, z is 1, w is the scale.
	vec3 ShadowmapCoord(void)
	{
		if (arg_spot)
		{
			//bias it. don't bother figuring out which side or anything, its not needed
			//l_projmatrix contains the light's projection matrix so no other magic needed
			return ((vtexprojcoord.xyz-vec3(0.0,0.0,0.015))/vtexprojcoord.w + vec3(1.0, 1.0, 1.0)) * vec3(0.5, 0.5, 0.5);
		}
	//	else if (CUBESHADOW)
	//	{
	//		vec3 shadowcoord = vshadowcoord.xyz / vshadowcoord.w;
	//		#define dosamp(x,y) shadowCube(s_shadowmap, shadowcoord + vec2(x,y)*texscale.xy).r
	//	}
		//figure out which axis to use
		//texture is arranged thusly:
		//forward left  up
		//back    right down
		vec3 dir = abs(vtexprojcoord.xyz);
		//assume z is the major axis (ie: forward from the light)
		vec3 t = vtexprojcoord.xyz;
		float ma = dir.z;
		vec3 axis = vec3(0.5/3.0, 0.5/2.0, 0.5);
		if (dir.x > ma)
		{
			ma = dir.x;
			t = vtexprojcoord.zyx;
			axis.x = 0.5;
		}
		if (dir.y > ma)
		{
			ma = dir.y;
			t = vtexprojcoord.xzy;
			axis.x = 2.5/3.0;
		}
		//if the axis is negative, flip it.
		if (t.z > 0.0)
		{
			axis.y = 1.5/2.0;
			t.z = -t.z;
		}

		//we also need to pass the result through the light's projection matrix too
		//the 'matrix' we need only contains 5 actual values. and one of them is a -1. So we might as well just use a vec4.
		//note: the projection matrix also includes scalers to pinch the image inwards to avoid sampling over borders, as well as to cope with non-square source image
		//the resulting z is prescaled to result in a value between -0.5 and 0.5.
		//also make sure we're in the right quadrant type thing
		return axis + ((l_shadowmapproj.xyz*t.xyz + vec3(0.0, 0.0, l_shadowmapproj.w)) / -t.z);
	}

	float ShadowmapFilter(void)
	{
		vec3 shadowcoord = ShadowmapCoord();

		#if 0//def GL_ARB_texture_gather
			vec2 ipart, fpart;
			#define dosamp(x,y) textureGatherOffset(s_shadowmap, ipart.xy, vec2(x,y)))
			vec4 tl = step(shadowcoord.z, dosamp(-1.0, -1.0));
			vec4 bl = step(shadowcoord.z, dosamp(-1.0, 1.0));
			vec4 tr = step(shadowcoord.z, dosamp(1.0, -1.0));
			vec4 br = step(shadowcoord.z, dosamp(1.0, 1.0));
			//we now have 4*4 results, woo
			//we can just average them for 1/16th precision, but that's still limited graduations
			//the middle four pixels are 'full strength', but we interpolate the sides to effectively give 3*3
			vec4 col =     vec4(tl.ba, tr.ba) + vec4(bl.rg, br.rg) + //middle two rows are full strength
					mix(vec4(tl.rg, tr.rg), vec4(bl.ba, br.ba), fpart.y); //top+bottom rows
			return dot(mix(col.rgb, col.agb, fpart.x), vec3(1.0/9.0));	//blend r+a, gb are mixed because its pretty much free and gives a nicer dot instruction instead of lots of adds.

		#else
	#ifdef USE_ARB_SHADOW
			//with arb_shadow, we can benefit from hardware acclerated pcf, for smoother shadows
			#define dosamp(x,y) shadow2D(s_shadowmap, shadowcoord.xyz + (vec3(x,y,0.0)*l_shadowmapscale.xyx)).r
	#else
			//this will probably be a bit blocky.
			#define dosamp(x,y) float(texture2D(s_shadowmap, shadowcoord.xy + (vec2(x,y)*l_shadowmapscale.xy)).r >= shadowcoord.z)
	#endif
			float s = 0.0;
			if (cvar_r_glsl_pcf < 5)
			{
				s += dosamp(0.0, 0.0);
				return s;
			}
			else if (cvar_r_glsl_pcf < 9)
			{
				s += dosamp(-1.0, 0.0);
				s += dosamp(0.0, -1.0);
				s += dosamp(0.0, 0.0);
				s += dosamp(0.0, 1.0);
				s += dosamp(1.0, 0.0);
				return s/5.0;
			}
			else
			{
				s += dosamp(-1.0, -1.0);
				s += dosamp(-1.0, 0.0);
				s += dosamp(-1.0, 1.0);
				s += dosamp(0.0, -1.0);
				s += dosamp(0.0, 0.0);
				s += dosamp(0.0, 1.0);
				s += dosamp(1.0, -1.0);
				s += dosamp(1.0, 0.0);
				s += dosamp(1.0, 1.0);
				return s/9.0;
			}
		#endif
	}
	vec3 LightingFuncShlick(vec3 N, vec3 V, vec3 L, float roughness, vec3 Cdiff, vec3 F0)
	{
		vec3 H = normalize(V+L);
		float NL = clamp(dot(N,L), 0.001, 1.0);
		float LH = clamp(dot(L,H), 0.0, 1.0);
		float NH = clamp(dot(N,H), 0.0, 1.0);
		float NV = clamp(abs(dot(N,V)), 0.001, 1.0);
		float VH = clamp(dot(V,H), 0.0, 1.0);
		float PI = 3.14159f;

		//Fresnel term
		//the fresnel models glancing light.
		//(Schlick)
		vec3 F = F0 + (1.0-F0)*pow(1.0-VH, 5.0);

		//Schlick
		float k = roughness*0.79788456080286535587989211986876;
		float G = (LH/(LH*(1.0-k)+k)) * (NH/(NH*(1.0-k)+k));

		//microfacet distribution
		float a = roughness*roughness;
		a *= a;
		float t = (NH*NH*(a-1.0)+1.0);

		float D = a/(PI*t*t);

		//if (r_glsl_fresnel == 1)
		//	return vec3(F);
		//if (r_glsl_fresnel == 2)
		//	return vec3(G);
		//if (r_glsl_fresnel == 3)
		//	return vec3(D);

		return ((1.0-F)*(Cdiff/PI) + 
			(F*G*D)/(4*NL*NV)) * NL;
	}

	#include "sys/fog.h"
	#include "sys/offsetmapping.h"

	void main ()
	{
		vec2 tex_c;
		vec3 normal_f;

		if (OFFSETMAPPING) {
			tex_c = offsetmap(s_normalmap, tcbase, eyevector);
		} else {
			tex_c = tcbase;
		}

		vec4 albedo_f = texture2D(s_diffuse, tex_c);

		if (BUMP) {
			normal_f = normalize(texture2D(s_normalmap, tex_c).rgb - 0.5);
		} else {
			normal_f = vec3(0.0, 0.0, 1.0);
		}

		float colorscale = max(1.0 - (dot(lightvector, lightvector)/(l_lightradius*l_lightradius)), 0.0);
		

		if (arg_pcf) {
			/* filter the light by the shadowmap. logically a boolean, but we allow fractions for softer shadows */
			colorscale *= ShadowmapFilter();
		}

		if (arg_spot) {
			/* filter the colour by the spotlight. discard anything behind the light so we don't get a mirror image */
			if (vtexprojcoord.w < 0.0) discard;
			vec2 spot = ((vtexprojcoord.st)/vtexprojcoord.w);
			colorscale*=1.0-(dot(spot,spot));
		}

		if (colorscale > 0)
		{
			vec3 out_f;

			if (UPPERLOWER) {
				vec4 uc = texture2D(s_upper, tex_c);
				albedo_f.rgb += uc.rgb*e_uppercolour*uc.a;
				vec4 lc = texture2D(s_lower, tex_c);
				albedo_f.rgb += lc.rgb*e_lowercolour*lc.a;
			}

			if (SPECULAR) {
				float metalness_f =texture2D(s_specular, tex_c).r;
				float roughness_f = texture2D(s_specular, tex_c).g;
				float ao = texture2D(s_specular, tex_c).b;

				vec3 nl = normalize(lightvector);
				out_f = albedo_f.rgb * (l_lightcolourscale.x + l_lightcolourscale.y * max(dot(normal_f.rgb, nl), 0.0));

				const vec3 dielectricSpecular = vec3(0.04, 0.04, 0.04);
				const vec3 black = vec3(0.0, 0.0, 0.0);
				vec3 F0 = mix(dielectricSpecular, albedo_f.rgb, metalness_f);
				albedo_f.rgb = mix(albedo_f.rgb * (1.0 - dielectricSpecular.r), black, metalness_f);

				out_f = LightingFuncShlick(normal_f.rgb, normalize(eyevector), nl, roughness_f, albedo_f.rgb, F0);

				vec3 cube_c = reflect(-eyevector, normal_f.rgb);
				cube_c = cube_c.x*invsurface[0] + cube_c.y*invsurface[1] + cube_c.z*invsurface[2];
				cube_c = vec4(m_model * vec4(cube_c.xyz,0.0)).xyz;

				out_f.rgb = out_f.rgb + (vec3(metalness_f,metalness_f,metalness_f) * textureCube(s_reflectcube, cube_c).rgb);
			}

			if (arg_cube) {
				/* filter the colour by the cubemap projection */
				out_f *= textureCube(s_projectionmap, vtexprojcoord.xyz).rgb;
			}

			gl_FragColor.rgb = fog3additive(out_f * colorscale * l_lightcolour);
		} else {
			gl_FragColor.rgb = vec3(0.0);
		}
	}
#endif 
