import { IsIn, IsNumber, ValidateNested } from 'class-validator';
import { Type } from 'class-transformer';

export class CoordinateDto {
  @IsNumber()
  latitude!: number;

  @IsNumber()
  longitude!: number;
}

export class CalculateRouteDto {
  @ValidateNested()
  @Type(() => CoordinateDto)
  origin!: CoordinateDto;

  @ValidateNested()
  @Type(() => CoordinateDto)
  destination!: CoordinateDto;

  @IsIn(['standard', 'motorcycle'])
  mode!: 'standard' | 'motorcycle';
}
