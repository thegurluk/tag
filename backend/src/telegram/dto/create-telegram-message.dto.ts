import { Transform } from 'class-transformer';
import { IsDateString, IsInt, IsNotEmpty, IsOptional, IsString } from 'class-validator';

const toNumber = ({ value }: { value: string | number | null | undefined }) =>
  value === null || value === undefined ? value : Number(value);

export class CreateTelegramMessageDto {
  @IsInt()
  @Transform(toNumber)
  telegram_message_id!: number;

  @IsInt()
  @Transform(toNumber)
  telegram_group_id!: number;

  @IsOptional()
  @IsInt()
  @Transform(toNumber)
  sender_id?: number | null;

  @IsString()
  @IsNotEmpty()
  raw_text!: string;

  @IsDateString()
  received_at!: string;
}
