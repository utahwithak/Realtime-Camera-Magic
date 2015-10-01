//
//  Shaders.metal
//  MagicPaint
//
//  Created by Carl Wieland on 9/29/15.
//  Copyright © 2015 Carl Wieland. All rights reserved.
//

#include <metal_stdlib>

using namespace metal;

struct VertexInOut
{
    float4  position [[position]];
    float2  uv;
    float3  lab;
};

vertex VertexInOut passThroughVertex(uint vid [[ vertex_id ]],
                                     constant packed_float4* position  [[ buffer(0) ]],
                                     constant packed_float2* uvs    [[ buffer(1) ]],
                                     constant float* labColors    [[ buffer(2) ]])
{
    VertexInOut outVertex;
    
    outVertex.position = position[vid];
    outVertex.uv    = uvs[vid];
    
//    outVertex.uv.x = 1 - outVertex.uv.x;
    outVertex.uv.y = 1 - outVertex.uv.y;
    outVertex.lab.r = labColors[0];
    outVertex.lab.g = labColors[1];
    outVertex.lab.b = labColors[2];
    return outVertex;
};

fragment half4 passThroughFragment(VertexInOut inFrag [[stage_in]],
                                   sampler texSmpl [[sampler(0)]],
                                   texture2d<half> tex [[ texture(0) ]])
{
    
    //color in
    half4 rgba = half4(tex.sample(texSmpl,inFrag.uv));
    half var_R = rgba.r;
    half var_G = rgba.g;
    half var_B = rgba.b;
    
    if ( var_R > 0.04045 ){
        var_R = pow(( ( var_R + 0.055 ) / 1.055 ), 2.4);
    }
    else{
        var_R = var_R / 12.92;
    }
    
    if ( var_G > 0.04045 ) {
        var_G = pow(( ( var_G + 0.055 ) / 1.055 ) , 2.4);
    }
    else{
        var_G = var_G / 12.92;
    }
    if ( var_B > 0.04045 ){
        var_B = pow(( ( var_B + 0.055 ) / 1.055 ), 2.4);
    }
    else{
        var_B = var_B / 12.92;
        
    }
    var_R = var_R * 100;
    var_G = var_G * 100;
    var_B = var_B * 100;
    
                            //Observer. = 2°, Illuminant = D65
    half X = var_R * 0.4124 + var_G * 0.3576 + var_B * 0.1805;
    half Y = var_R * 0.2126 + var_G * 0.7152 + var_B * 0.0722;
    half Z = var_R * 0.0193 + var_G * 0.1192 + var_B * 0.9505;
    
    half var_X = X / 95.047;//ref_X          //ref_X =  95.047   Observer= 2°, Illuminant= D65
    half var_Y = Y / 100.000;          //ref_Y = 100.000
    half var_Z = Z / 108.883;          //ref_Z = 108.883
    
    if ( var_X > 0.008856 ){
        var_X = pow(var_X,(half)0.333333333333f);
    }
    else{
        var_X = ( 7.787 * var_X ) + ( 16 / 116 );
    }
    if ( var_Y > 0.008856 ){
        var_Y = pow(var_Y ,(half)0.333333333333f);
    }
    else{
        var_Y = ( 7.787 * var_Y ) + ( 16 / 116 );
    }
    if ( var_Z > 0.008856 ){
        var_Z = pow(var_Z,(half)0.333333333333f);
    }
    else{
        var_Z = ( 7.787 * var_Z ) + ( 16 / 116 );
    }
    //http://www.brucelindbloom.com/index.html?Equations.html
    float L2 = ( 116 * var_Y ) - 16;
    float a2 = 500 * ( var_X - var_Y );
    float b2 = 200 * ( var_Y - var_Z );
    
    float L1 = inFrag.lab.r;
    float a1 = inFrag.lab.g;
    float b1 = inFrag.lab.b;
    
    
    float delL = (L1 - L2);
    float dela = (a1 - a2);
    float delb = (b1 - b2);
    float delta = sqrt((delL * delL) + (dela * dela) + (delb * delb) );
    
    if(delta < 40){
//        //        float dif = 100.0 - delta / 100.0;
//        half mixr = 187.0/255.0;// * dif;
//        half mixg =  153.0/255.0;// * dif;
//        half mixb = 133.0/255.0 ;//* dif;
        
        return half4(1,1,1, 1);
    }
    else{
        return rgba;
    }
};
