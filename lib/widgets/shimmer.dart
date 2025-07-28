import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:sizer/sizer.dart';

class ShimmerLayout extends StatelessWidget {
  const ShimmerLayout({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Shimmer.fromColors(
                    baseColor: Colors.grey[300]!,
                    highlightColor: Colors.grey[100]!,
                    child: Container(
                      width: 50,
                      height: 30,
                      color: Colors.grey[300],
                    ),
                  ),
                ],
              ),
              // Section principale
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Colonne de gauche (texte)
                  Expanded(
                    flex: 2,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildShimmerText(40, double.infinity),
                        const SizedBox(height: 20),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 300),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 250),
                        const SizedBox(height: 20),
                        _buildShimmerText(15, 200),
                        const SizedBox(height: 10),
                        _buildShimmerText(15, 280),
                        const SizedBox(height: 20),
                        _buildShimmerText(15, 260),
                        const SizedBox(height: 20),
                        _buildShimmerText(15, 260),
                        const SizedBox(height: 20),
                        _buildShimmerText(15, 260),
                        const SizedBox(height: 20),
                        _buildShimmerText(15, 260),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),

                  // Colonne de droite (grid)
                  Expanded(
                    flex: 3,
                    child: Column(
                      children: [
                        _buildShimmerGrid(),
                      ],
                    ),
                  ),
                ],
              ),

              // TextField en bas à gauche
              Padding(
                padding: EdgeInsets.only(top: 5.h),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width * 0.4,
                    child: Shimmer.fromColors(
                      baseColor: Colors.grey[300]!,
                      highlightColor: Colors.grey[100]!,
                      child: Container(
                        height: 50,
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerText(double height, double width) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }

  Widget _buildShimmerGrid() {
    return Padding(
      padding: EdgeInsets.only(left: 2.w, right: 2.w),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 1.5,
        children: List.generate(9, (index) {
          return Shimmer.fromColors(
            baseColor: Colors.grey[300]!,
            highlightColor: Colors.grey[100]!,
            child: Container(
              height: 30.h,
              width: 20.w,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }),
      ),
    );
  }
}
