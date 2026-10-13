#ifndef SPACE_GLSL
    #define SPACE_GLSL a

    vec3 viewSpacePosition(vec2 uv,float depth){
        vec4 v=gbufferProjectionInverse*vec4(uv*2.-1.,depth*2.-1.,1.);
        return v.xyz/v.w;
    }

    vec3 worldSpacePosition(vec2 uv,float depth){
        return (gbufferModelViewInverse*vec4(viewSpacePosition(uv,depth),1.)).xyz;
    }

    float viewDepth(float d){
        return -gbufferProjection[3][2]/(d*2.-1.+gbufferProjection[2][2]);
    }

    vec3 viewToWorldDir(vec3 v){
        return normalize(mat3(gbufferModelViewInverse)*v);
    }

    vec3 worldToViewDir(vec3 v){
        return normalize(mat3(gbufferModelView)*v);
    }

    vec3 sunDirection(){
        return normalize(sunDir);
    }

    vec3 lightDirection(){
        return viewToWorldDir(shadowLightPosition);
    }

#endif
