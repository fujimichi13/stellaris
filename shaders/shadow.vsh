#version 430 compatibility

out vec4 glcolor;
out vec2 texcoord;

void main(){
    glcolor = gl_Color;
    texcoord = (gl_TextureMatrix[0] * gl_MultiTexCoord0).xy;
    gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
}