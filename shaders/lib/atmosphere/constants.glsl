#ifndef ATMOS_CONSTANTS
    #define ATMOS_CONSTANTS a

    #define PI 3.14159265359
    #define LUT_SAMPLES 16
    #define SCATTER_SAMPLES 24

    const float A_r=6371.;
    const float A_R=6371.+32.;

    const float density=100.*10e-6;

    const vec3 ray_s=vec3(5.802,13.558,33.1)*density;
    const vec3 ray_e=ray_s;

    const vec3 mie_s=vec3(3.996)*density;
    const vec3 mie_e=mie_s+vec3(1.,2.,4.4)*density;

    const vec3 ozo_e=vec3(.65,1.881,.085)*density;

    struct DensityProfileLayer{
        float width;
        float exp_term;
        float exp_scale;
        float linear_term;
        float constant_term;
    };

    struct DensityProfile{
        DensityProfileLayer layers[2];
    };

    const DensityProfile rayleigh_density=DensityProfile(DensityProfileLayer[](
        DensityProfileLayer(0.,0.,0.,0.,0.),
        DensityProfileLayer(0.,1.,-1000./8000.,0.,0.)
    ));

    const DensityProfile mie_density=DensityProfile(DensityProfileLayer[](
        DensityProfileLayer(0.,0.,0.,0.,0.),
        DensityProfileLayer(0.,1.,-1000./1200.,0.,0.)
    ));

    const DensityProfile absorption_density=DensityProfile(DensityProfileLayer[](
        DensityProfileLayer(25.,0.,0.,1000./15000.,-2./3.),
        DensityProfileLayer(0.,0.,0.,-1000./15000.,8./3.)
    ));

#endif