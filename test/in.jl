@testset "in" begin
    X = [
        -2 2 0 0
        0 0 -1 1
    ]

    ϵ = minimum_volume_ellipsoid(X, 1e-10; centered=true)

    # test point inside
    point = [0;0]
    @test in(ϵ,point) == true
    # test point outside ellipse
    point = [2;1]
    @test in(ϵ,point) == false
    # test point on the border of ellipse
    point = [1;sqrt(3/4)]
    @test in(ϵ,point) == true
end