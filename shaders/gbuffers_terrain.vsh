#version 430 compatibility

uniform mat4 gbufferModelViewInverse;

in vec4 at_tangent;

out vec4 glcolor;
out vec2 texcoord;
out vec2 vlightmap;
out vec3 vNormal;
out vec3 vTangent;
out vec3 vBitangent;

void main(){
    glcolor=gl_Color;
    texcoord=(gl_TextureMatrix[0]*gl_MultiTexCoord0).xy;
    vlightmap=(gl_TextureMatrix[1]*gl_MultiTexCoord1).xy;

    mat3 toWorld=mat3(gbufferModelViewInverse);
    vec3 N=normalize(toWorld*(gl_NormalMatrix*gl_Normal));
    vec3 T=normalize(toWorld*(gl_NormalMatrix*at_tangent.xyz));
    vec3 B=normalize(cross(T,N)*at_tangent.w);
    vNormal=N;
    vTangent=T;
    vBitangent=B;

    gl_Position=gl_ProjectionMatrix*gl_ModelViewMatrix*gl_Vertex;
}