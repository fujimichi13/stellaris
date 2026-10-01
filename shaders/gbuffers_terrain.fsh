#version 430 compatibility

#include "/lib/surface/brdf.glsl"

uniform sampler2D tex;
uniform sampler2D normals;
uniform sampler2D specular;

in vec4 glcolor;
in vec2 texcoord;
in vec2 vlightmap;
in vec3 vNormal;
in vec3 vTangent;
in vec3 vBitangent;

/* RENDERTARGETS: 0,2,3,4 */
layout(location = 0) out vec4 color;
layout(location = 1) out vec4 color2;
layout(location = 2) out vec4 color3;
layout(location = 3) out vec4 color4;

void main(){
    vec4 albedo=texture(tex,texcoord)*glcolor;
    if(albedo.a<.1){
        discard;
    }

    vec4 spec=texture(specular,texcoord);
    vec4 nt=texture(normals,texcoord);

    float ao;
    vec3 N=decodeLabPBRNormal(nt,mat3(normalize(vTangent),normalize(vBitangent),normalize(vNormal)),ao);

    vec2 lm=saturate((vlightmap-.03125)/.9375);

    color=vec4(albedo.rgb,albedo.a);
    color2=spec;
    color3=vec4(N,ao);
    color4=vec4(lm,0.,1.);
}