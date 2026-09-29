#version 430 compatibility

uniform sampler2D tex;
uniform sampler2D lightmap;

in vec4 glcolor;
in vec2 texcoord;
in vec2 vlightmap;

/* RENDERTARGETS: 0 */
layout(location = 0 ) out vec4 color;

void main(){
    vec4 albedo=texture(tex,texcoord)*glcolor;

    if(albedo.a<.1){
        discard;
    }

    vec3 light=texture(lightmap,vlightmap).rgb;

    color=vec4(albedo.rgb*light,albedo.a);
}